# Runs `kamal app logs` for a LogSession and streams scrubbed lines to the app
# page. Follow mode runs until stopped, or until follow_limit so a forgotten
# tab can't hold an ssh session open forever.
class LogSessionJob < ApplicationJob
  RECENT_LINES = 200

  class_attribute :follow_limit, default: 15.minutes

  queue_as :logs
  discard_on ActiveJob::DeserializationError

  def perform(session)
    return unless session.reload.running?

    status = command_for(session).run(on_start: ->(pid) { started(session, pid) }) do |line|
      session.append_line(line)
    end
    session.finish_as(status.success? ? "finished" : "failed")
  rescue StandardError => error
    session.append_line(SecretScrubber.scrub("grateful-deploy: #{error.class}: #{error.message}"))
    session.finish_as("failed")
  end

  private

  def command_for(session)
    if session.follow_mode?
      KamalCommand.new(session.app, :logs_follow)
    else
      KamalCommand.new(session.app, :logs, lines: RECENT_LINES)
    end
  end

  def started(session, pid)
    return unless session.started!(pid) && session.follow_mode?

    limit = follow_limit
    Thread.new do
      sleep limit
      Rails.application.executor.wrap { LogSession.find(session.id).stop! }
    end
  end
end
