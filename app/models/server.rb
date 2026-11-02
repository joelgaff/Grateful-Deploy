class Server < ApplicationRecord
  belongs_to :organization
  has_many :apps, dependent: :destroy
  has_many :server_snapshots, dependent: :delete_all
  has_one :latest_server_snapshot, -> { order(checked_at: :desc) }, class_name: "ServerSnapshot"

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  # Both go straight into ssh's arguments as user@host: a plain name or address, never an option.
  validates :host, presence: true, format: { with: /\A[a-z0-9][a-z0-9.:-]*\z/i, message: "must be a hostname or IP address" }
  validates :ssh_user, format: { with: /\A[a-z_][a-z0-9_.-]*\z/i, message: "must be a plain user name" }
  validates :proxy_http_port, :proxy_https_port, numericality: { only_integer: true, in: 1..65535 }
  normalizes :name, :host, :ssh_user, :region, with: ->(value) { value.strip }
  normalizes :notes, with: ->(value) { value.squish.presence }

  # One round of read-only SSH for the whole server, then a health check per app.
  # An SSH failure is recorded on the snapshots rather than raised.
  def refresh_status!(probe: ServerProbe.new(self), health: ->(app) { HealthCheck.new(app).call })
    checked_at = Time.current
    resources, ssh_error = read_resources(probe)
    record_server_snapshot(resources, ssh_error, checked_at)
    record_app_snapshots(resources&.fetch(:containers) || [], ssh_error, health, checked_at)
    broadcast_panel
  end

  def broadcast_panel
    fresh = Server.includes(:apps, :latest_server_snapshot).find(id)
    broadcast_replace_to "servers", target: ActionView::RecordIdentifier.dom_id(self, :panel),
                                    partial: "servers/panel", locals: { server: fresh }
  end

  private

  def read_resources(probe)
    [ { containers: probe.containers, memory: probe.memory, disk: probe.disk, load: probe.load,
        kamal_locks: probe.kamal_locks }, nil ]
  rescue ServerProbe::Error => error
    [ nil, error.message ]
  end

  def record_server_snapshot(resources, ssh_error, checked_at)
    memory, disk, load = resources&.values_at(:memory, :disk, :load)
    server_snapshots.create!(
      memory_total: memory&.total, memory_used: memory&.used, memory_available: memory&.available,
      swap_total: memory&.swap_total, swap_used: memory&.swap_used,
      disk_total: disk&.total, disk_used: disk&.used, disk_available: disk&.available,
      load_1: load&.one, load_5: load&.five, load_15: load&.fifteen, cpus: load&.cpus,
      containers: (resources&.fetch(:containers) || []).select(&:running?).map { |container| container.to_h.merge(version: container.version) },
      kamal_locks: resources&.fetch(:kamal_locks),
      error: ssh_error,
      checked_at: checked_at
    )
  end

  # Each service's running web container, or if none runs, its newest stopped
  # one (docker ps -a lists newest first; Kamal keeps old versions stopped).
  def web_containers(containers)
    containers.select(&:web?).group_by(&:service).transform_values { |list| list.find(&:running?) || list.first }
  end

  def record_app_snapshots(containers, ssh_error, health, checked_at)
    web = web_containers(containers)

    apps.where(active: true).find_each do |app|
      container = web[app.service]
      # A stopped app has nothing to answer; checking would only show the proxy's error.
      check = container&.running? == false ? HealthCheck::Result.new(code: nil, response_ms: nil, error: nil) : health.(app)
      app.status_snapshots.create!(
        version: container&.version,
        container_state: ssh_error ? nil : container&.state || "missing",
        container_status: container&.status,
        memory_bytes: container&.memory_bytes,
        health_code: check.code,
        response_ms: check.response_ms,
        error: ssh_error || check.error,
        checked_at: checked_at
      )
      app.broadcast_card
      app.broadcast_page
    end
  end
end
