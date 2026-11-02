class App < ApplicationRecord
  belongs_to :server
  has_many :deploys, dependent: :destroy
  # The latest deploy or rollback; a lock release isn't one.
  has_one :latest_deploy, -> { where(kind: %w[deploy rollback]).order(created_at: :desc) }, class_name: "Deploy"
  has_many :status_snapshots, dependent: :delete_all
  has_many :log_sessions, dependent: :delete_all
  has_one :latest_status_snapshot, -> { order(checked_at: :desc) }, class_name: "StatusSnapshot"
  # The latest check that saw a container, so one failed check (locked
  # 1Password, ssh rate limit) doesn't lose the running version.
  has_one :running_status_snapshot, -> { where.not(version: nil).order(checked_at: :desc) }, class_name: "StatusSnapshot"

  enum :kamal_mode, { destination: "destination", config_file: "config_file" }, suffix: :mode
  enum :kamal_binary, { bundled: "bundled", global: "global" }

  validates :name, presence: true, uniqueness: { scope: :server_id }
  validates :service, :repo_path, presence: true
  validates :destination, presence: true, if: :destination_mode?
  validates :config_file, presence: true, if: :config_file_mode?
  validate :repo_path_is_absolute
  validate :name_is_unused_on_other_servers
  validate :kamal_env_is_plain_text

  # The one way a deploy or rollback gets queued. Raises if one is already in flight.
  def start_deploy!(kind: "deploy", version: nil, triggered_by: "ui")
    commit = kind.to_s == "deploy" ? GitHead.read(repo_path) : {}
    deploys.create!(kind: kind, version: version, triggered_by: triggered_by, **commit).tap do |deploy|
      DeployJob.perform_later(deploy)
    end
  end

  # A deploy or rollback that Kamal's post-deploy hook reported from outside
  # Grateful Deploy (a terminal, CI). Grateful Deploy's own deploys report through
  # the same hook while they're still running; those are ignored (nil).
  # A version with uncommitted changes is noted but never offered for rollback.
  def record_outside_deploy!(command:, version:, runtime:)
    return if deploy_in_flight?

    sha = version.to_s if version.to_s.match?(GitHead::SHA)
    rollback = command == "rollback" && sha
    detail = sha ? "" : ", version #{version.to_s.first(7)} with uncommitted changes"
    finished_at = Time.current
    deploys.create!(
      kind: rollback ? "rollback" : "deploy", status: "succeeded", triggered_by: "outside",
      version: (sha if rollback), git_sha: (sha unless rollback),
      started_at: finished_at - runtime.to_f.seconds, finished_at: finished_at,
      log: "Deployed outside Grateful Deploy (kamal #{command}#{detail}). Its output isn't recorded here.\n", log_lines: 1
    ).tap { RefreshStatusJob.perform_later(force: true) }
  end

  ROLLBACK_CHOICES = 5 # Kamal keeps the last 5 containers by default

  # Versions this app is known to have run successfully, newest first,
  # excluding the one running now. Rollbacks may only pick from these.
  def rollback_versions
    last_seen = Hash.new { |hash, version| hash[version] = Time.at(0) }

    deploys.succeeded.each do |deploy|
      version = deploy.rollback_kind? ? deploy.version : deploy.git_sha
      last_seen[version] = [ last_seen[version], deploy.finished_at || deploy.created_at ].max
    end
    status_snapshots.where(container_state: "running", health_code: 200..299)
      .group(:version).maximum(:checked_at)
      .each { |version, checked_at| last_seen[version] = [ last_seen[version], checked_at ].max }

    last_seen.except(nil, running_status_snapshot&.version)
      .sort_by { |_, seen_at| seen_at }.reverse.first(ROLLBACK_CHOICES).map(&:first)
  end

  # Why Deploy and Rollback are off, if they are: a kamal_env value in
  # fleet.yml isn't set yet (Kamal would deploy with deploy.yml's
  # placeholder), or Kamal's own lock is held by a deploy Grateful Deploy
  # didn't start.
  def deploy_blocked_reason
    missing = kamal_env.select { |_, value| value.blank? }.keys
    return "Set #{missing.to_sentence} in config/fleet.yml before deploying #{name}" if missing.any?

    if (lock = kamal_lock) && !deploy_in_flight?
      "Kamal's deploy lock for #{name} is held (#{lock.lines.first.strip}). Wait for that deploy to finish, or release the lock"
    end
  end

  # The stopped container's version, which Start boots again; nil unless the
  # latest check found this app stopped.
  def stopped_version
    snapshot = latest_status_snapshot
    snapshot.version if snapshot&.stopped?
  end

  def running?
    latest_status_snapshot&.container_state == "running"
  end

  # Why Release lock is off: there's no lock to release, or kamal_env is incomplete.
  def release_lock_blocked_reason
    missing = kamal_env.select { |_, value| value.blank? }.keys
    return "Set #{missing.to_sentence} in config/fleet.yml before deploying #{name}" if missing.any?

    "No Kamal deploy lock is held for #{name}" unless kamal_lock
  end

  # Kamal's deploy lock for this app as the latest status check saw it (who,
  # when, version, message), or nil: not held, or the check couldn't read it.
  def kamal_lock
    server.latest_server_snapshot&.kamal_locks&.dig(kamal_lock_name)
  end

  # Kamal's lock folder name (Kamal::Commands::Lock#lock_dir).
  def kamal_lock_name
    [ "lock", service, (destination if destination_mode?) ].compact.join("-")
  end

  def running_log_session
    log_sessions.running.last
  end

  def deploy_in_flight?
    deploys.in_flight.exists?
  end

  # The domain to link to: the first real one, not the sslip.io test host.
  def primary_domain
    domains.find { |domain| !domain.end_with?(".sslip.io") } || domains.first
  end

  # Re-renders this app's card on the apps page with fresh status and deploy.
  def broadcast_card
    fresh = App.includes(:latest_status_snapshot, :running_status_snapshot, :latest_deploy).find(id)
    broadcast_replace_to "apps", target: ActionView::RecordIdentifier.dom_id(self, :card),
                                 partial: "apps/card", locals: { app: fresh }
  end

  PAGE_PARTS = %i[header deploy_controls facts rollbacks deploy_history].freeze

  # Re-renders the parts of this app's page that change as deploys run and
  # status checks come in.
  def broadcast_page
    PAGE_PARTS.each do |part|
      broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, part),
                                 partial: "apps/#{part}", locals: { app: self }
    end
  end

  def kamal_executable
    global? ? GlobalKamal.path : "bin/kamal"
  end

  def kamal_target_args
    destination_mode? ? [ "-d", destination ] : [ "-c", config_file ]
  end

  private

  # Fleet.import finds an app that moved between servers by its name.
  def name_is_unused_on_other_servers
    return if server.nil? || name.blank?

    other = App.joins(:server).where(name: name, servers: { organization_id: server.organization_id }).where.not(id: id).first
    errors.add(:name, "is already used by an app on #{other.server.name}") if other
  end

  def repo_path_is_absolute
    errors.add(:repo_path, "must be an absolute path") if repo_path.present? && !repo_path.start_with?("/")
  end

  # Plain settings a repo's deploy.yml reads from ENV (a server IP, a domain),
  # never secrets: those stay in the repo's own .env, out of fleet.yml.
  def kamal_env_is_plain_text
    unless kamal_env.is_a?(Hash) && kamal_env.all? { |name, value| name.match?(/\A[A-Z][A-Z0-9_]*\z/) && (value.nil? || value.is_a?(String)) }
      return errors.add(:kamal_env, "must map UPPER_CASE names to text")
    end

    kamal_env.each_key do |name|
      if name.match?(/\A(?:#{SecretScrubber::SECRET_NAME}|#{SecretScrubber::ENV_KEY_NAME})\z/)
        errors.add(:kamal_env, "can't hold secrets (#{name}); keep them in the repo's .env")
      end
    end
  end
end
