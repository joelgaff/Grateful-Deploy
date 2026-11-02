class StatusSnapshot < ApplicationRecord
  RETENTION = 1.week

  belongs_to :app

  def self.prune
    where(checked_at: ...RETENTION.ago).delete_all
  end

  def healthy?
    container_state == "running" && health_code.present? && (200..299).cover?(health_code)
  end

  # Running, but there was nothing to health-check (an HTTPS app with no domain yet).
  def running_unchecked?
    container_state == "running" && health_code.nil? && error == HealthCheck::NO_DOMAIN
  end

  # Its container exists but isn't running. Kamal runs containers with Docker's
  # unless-stopped policy, so a crash restarts it; only a stop (kamal app stop) leaves it exited.
  def stopped?
    container_state.in?(%w[exited created])
  end

  def short_version
    version&.first(7)
  end
end
