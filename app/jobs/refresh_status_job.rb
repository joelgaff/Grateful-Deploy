# Checks each server's containers and resources over SSH, and each app's
# health. Scheduled every 2 minutes; Refresh now forces it.
#
# A scheduled run skips a server checked (even unsuccessfully) less than a
# minute ago: after the laptop sleeps, Solid Queue enqueues every missed run
# at once, and hundreds of SSH connections would trip the server's ufw rate
# limit (and block deploys) until they drained.
class RefreshStatusJob < ApplicationJob
  MIN_INTERVAL = 1.minute

  # How a server is checked; tests swap it so no SSH is opened.
  class_attribute :refresher, default: ->(server) { server.refresh_status! }

  queue_as :status

  def perform(force: false)
    Server.includes(:latest_server_snapshot).find_each do |server|
      refresher.call(server) if force || due?(server)
    end
    StatusSnapshot.prune
    ServerSnapshot.prune
  end

  private

  def due?(server)
    last = server.latest_server_snapshot&.checked_at
    last.nil? || last < MIN_INTERVAL.ago
  end
end
