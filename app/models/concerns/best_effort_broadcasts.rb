# Page redraws (Turbo broadcasts, including rendering the partial) are best
# effort: one that fails is logged and skipped, never allowed to break the
# status change, deploy or status check that triggered it. The page catches
# up on its next update.
module BestEffortBroadcasts
  def broadcast_replace_to(...)
    super
  rescue StandardError => error
    log_failed_broadcast(error)
  end

  def broadcast_append_to(...)
    super
  rescue StandardError => error
    log_failed_broadcast(error)
  end

  private

  def log_failed_broadcast(error)
    Rails.logger.error("#{self.class.name} #{id}: page update failed: #{error.class}: #{error.message}")
  end
end
