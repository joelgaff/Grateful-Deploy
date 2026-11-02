# What a deploy would ship right now, read from the app's local repo: the
# HEAD commit Kamal builds, compared with the version the server is running.
class ShipPreview
  # Kamal reads its own config and secrets from the working folder, so those
  # take effect uncommitted; everything else is built from a clean clone of HEAD.
  KAMAL_FILES = [ ":(exclude,glob)config/deploy*.yml", ":(exclude).kamal" ].freeze

  MAIN_BRANCHES = %w[main master].freeze

  # fresh_ci: ask GitHub about CI now (page load, Deploy click, Check CI);
  # otherwise reuse the last answer.
  def initialize(app, fresh_ci: false)
    @app, @fresh_ci = app, fresh_ci
  end

  def readable?
    head_sha.present?
  end

  def head_short_sha
    head_sha&.first(7)
  end

  # nil when HEAD is detached.
  def branch
    @branch ||= GitHead.git(@app.repo_path, "rev-parse", "--abbrev-ref", "HEAD")&.chomp&.then { it unless it == "HEAD" }
  end

  def main_branch?
    MAIN_BRANCHES.include?(branch)
  end

  # See CiSignoff#state; nil when HEAD can't be read.
  def ci_state
    @ci_state ||= CiSignoff.new(@app.repo_path, head_sha).state(fresh: @fresh_ci) if readable?
  end

  def ci_checkable?
    ci_state.in?(%i[failed missing unknown unchecked])
  end

  def ahead
    counts&.last
  end

  def behind
    counts&.first
  end

  def running_version
    running_snapshot&.version
  end

  # When the latest status check failed, the time the running version was
  # last seen; nil when it is current.
  def running_seen_at
    running_snapshot.checked_at if running_snapshot && running_snapshot != @app.latest_status_snapshot
  end

  # Modified, staged or new (not ignored) files that won't ship.
  def uncommitted_changes?
    return @uncommitted_changes if defined?(@uncommitted_changes)

    @uncommitted_changes = GitHead.git(@app.repo_path, "status", "--porcelain", "--", ".", *KAMAL_FILES).present?
  end

  private

  def head_sha
    @head_sha ||= GitHead.git(@app.repo_path, "rev-parse", "HEAD")&.chomp
  end

  def running_snapshot
    @app.running_status_snapshot
  end

  def counts
    return unless running_version&.match?(GitHead::SHA) && head_sha

    @counts ||= GitHead.git(@app.repo_path, "rev-list", "--left-right", "--count", "#{running_version}...#{head_sha}")&.split&.map(&:to_i)
  end
end
