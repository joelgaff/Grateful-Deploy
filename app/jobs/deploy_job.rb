# Runs a queued Deploy (deploy or rollback) through KamalCommand, streaming
# scrubbed output to the deploy's page. Whatever happens, the deploy ends
# succeeded, failed or canceled — never stuck running, which would hold the
# app's lock. A deploy still running after time_limit is stopped.
class DeployJob < ApplicationJob
  class_attribute :time_limit, default: 20.minutes

  queue_as :deploys
  discard_on ActiveJob::DeserializationError

  def perform(deploy)
    return unless deploy.start!

    watchdog = nil
    command = KamalCommand.new(deploy.app, deploy.kind, version: deploy.version)
    status = command.run(on_start: ->(pid) { deploy.update_column(:pid, pid); watchdog = watch(deploy) }) do |line|
      deploy.append_line(line)
    end
    deploy.finish!(status.exitstatus)
  rescue StandardError => error
    Rails.logger.error("DeployJob #{deploy.id} failed: #{error.class}: #{error.message}")
    deploy.append_line("grateful-deploy: #{error.class}: #{error.message}")
    deploy.finish!(nil)
  ensure
    # A watchdog that has fired is stopping Kamal and writing its note; let it
    # finish. One still sleeping is no longer needed.
    watchdog&.[](:fired) ? watchdog.join(15) : watchdog&.kill
    # Check status now: the new version shows, and this deploy's own Kamal
    # lock, seen mid-deploy, clears instead of blocking Deploy for 2 minutes.
    RefreshStatusJob.perform_later(force: true) if deploy.started_at
  end

  private

  def watch(deploy)
    limit = time_limit
    Thread.new do
      sleep limit
      Thread.current[:fired] = true
      Rails.application.executor.wrap { Deploy.find(deploy.id).time_out!(limit) }
    end
  end
end
