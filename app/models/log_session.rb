# One `kamal app logs` run for an app: the last N lines, or a live follow.
# Lines are broadcast to the app page and never stored.
class LogSession < ApplicationRecord
  belongs_to :app

  enum :mode, { recent: "recent", follow: "follow" }, suffix: true
  enum :status, { running: "running", finished: "finished", stopped: "stopped", failed: "failed" }

  validate :one_running_per_app, if: :running?

  after_create_commit :broadcast_controls

  # Sessions still running when Solid Queue starts lost their job; their
  # processes may still be alive in their own group, so stop those too.
  def self.stop_abandoned!
    running.find_each(&:stop!)
  end

  # The job launched Kamal; the controls switch from "Waiting to start".
  # If Stop was pressed before the pid was known, ends Kamal now and returns false.
  def started!(pid)
    if update_if_running(pid: pid)
      broadcast_controls
      true
    else
      ProcessGroup.terminate(pid, grace: 5)
      false
    end
  end

  def append_line(line)
    line = SecretScrubber.scrub(line)
    broadcast_append_to [ app, :logs ], target: ActionView::RecordIdentifier.dom_id(app, :logs),
                                        partial: "deploys/line", locals: { line: line }
  end

  # Moves a running session to its final status. A single conditional UPDATE,
  # so when Stop and the job's own finish race, the first one wins.
  def finish_as(final_status)
    moved = update_if_running(status: final_status, finished_at: Time.current)
    broadcast_controls if moved
    moved
  end

  # Marks the session stopped first (so the job's finish can't overwrite it),
  # then stops Kamal and everything it spawned. The pid is read after that
  # update; a Kamal that starts later is ended by #started!.
  def stop!
    ProcessGroup.terminate(pid, grace: 5) if finish_as("stopped") && pid
  end

  private

  # One conditional UPDATE, so whichever of Stop and the job gets there first wins.
  def update_if_running(attributes)
    updated = self.class.where(id: id, status: "running").update_all(attributes.merge(updated_at: Time.current)) == 1
    reload
    updated
  end

  def broadcast_controls
    broadcast_replace_to [ app, :logs ], target: ActionView::RecordIdentifier.dom_id(app, :log_controls),
                                         partial: "log_sessions/controls", locals: { app: app }
  end

  def one_running_per_app
    if app && LogSession.running.where(app: app).where.not(id: id).exists?
      errors.add(:base, "#{app.name} is already showing logs")
    end
  end
end
