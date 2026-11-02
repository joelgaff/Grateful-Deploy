class Deploy < ApplicationRecord
  IN_FLIGHT = %w[queued running].freeze

  belongs_to :app

  enum :kind, { deploy: "deploy", rollback: "rollback", release_lock: "release_lock", stop: "stop", start: "start" }, suffix: true
  enum :status, { queued: "queued", running: "running", succeeded: "succeeded", failed: "failed", canceled: "canceled" }
  enum :triggered_by, { ui: "ui", git_hook: "git_hook", outside: "outside" }

  scope :in_flight, -> { where(status: IN_FLIGHT) }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  validates :version, format: { with: GitHead::SHA }, if: -> { rollback_kind? || start_kind? }
  validate :one_in_flight_per_app, if: -> { status.in?(IN_FLIGHT) }
  validate :app_ready_to_deploy, on: :create, unless: :outside? # it already happened

  after_create_commit -> { app.broadcast_page }

  # A deploy still running when Solid Queue starts lost its worker (Grateful Deploy
  # was stopped or crashed). Fail it so it stops holding the app's lock.
  # Its Kamal may still be running in its own process group; stop that too.
  def self.fail_abandoned!
    running.find_each do |deploy|
      deploy.append_line("Grateful Deploy restarted while this was running. Kamal may have finished " \
                         "or stopped part way; check the app before deploying again.")
      deploy.finish!(nil)
      ProcessGroup.terminate(deploy.pid) if deploy.pid
    end
  end

  # Re-applies SecretScrubber to saved logs, e.g. after its rules improve.
  def self.rescrub_logs!
    find_each do |deploy|
      scrubbed = deploy.log.each_line.map { |line| SecretScrubber.scrub(line.chomp) + "\n" }.join
      deploy.update_column(:log, scrubbed) unless scrubbed == deploy.log
    end
  end

  # Status changes are single conditional UPDATEs, so when the job, a Cancel
  # and the time limit race, the first final status wins and a canceled
  # deploy that was still queued never starts.
  def start!
    transition(from: "queued", to: "running", started_at: Time.current).tap { broadcast_status if it }
  end

  # Saves the line, then streams it to anyone watching, so a page opened at
  # any moment finds every line already shown. One UPDATE appends and numbers
  # it, so lines from another process (a Cancel) keep their order. Returns
  # the line's number. Multi-line text (an error message) goes in as one
  # numbered line each, so the numbers always match the saved log's lines.
  def append_line(line)
    return line.lines.map { append_line(it.chomp) }.last if line.include?("\n")

    line = SecretScrubber.scrub(line)
    # exec_query, not select_value: it always runs and clears the query cache.
    number = self.class.connection.exec_query(self.class.sanitize_sql_array([
      "UPDATE deploys SET log = log || ?, log_lines = log_lines + 1, updated_at = ? WHERE id = ? RETURNING log_lines",
      "#{line}\n", Time.current, id
    ])).rows.first&.first
    broadcast_append_to self, target: ActionView::RecordIdentifier.dom_id(self, :log),
                              partial: "deploys/line", locals: { line: line, number: number, deploy: self }
    number
  end

  def finish!(exit_code)
    transition(from: "running", to: exit_code&.zero? ? "succeeded" : "failed",
               exit_code: exit_code, finished_at: Time.current).tap { broadcast_status if it }
  end

  def cancel!
    stop(as: "canceled", from: IN_FLIGHT, note: "Canceled from Grateful Deploy.")
  end

  def time_out!(limit)
    stop(as: "failed", from: "running", note: "Stopped after the #{describe(limit)} time limit.")
  end

  # [text, number] for each saved line after number `after`.
  def numbered_lines(after: 0)
    log.each_line.with_index(1).drop(after).map { |line, number| [ line.chomp, number ] }
  end

  # Lines on the page are numbered, so a late-arriving line goes in its place
  # and one already shown isn't shown twice.
  def line_dom_id(number)
    "deploy_#{id}_line_#{number}"
  end

  def duration
    finished_at - started_at if started_at && finished_at
  end

  private

  # Records the final status first (so the job's own finish can't overwrite
  # it), then stops Kamal and everything it spawned, and only then touches
  # the log and the pages, so nothing there can keep Kamal running.
  def stop(as:, from:, note:)
    return false unless transition(from: from, to: as, finished_at: Time.current)

    ProcessGroup.terminate(pid) if pid
    append_line("grateful-deploy: #{note}")
    broadcast_status
    true
  end

  def describe(limit)
    limit.is_a?(ActiveSupport::Duration) ? limit.inspect.singularize : "#{limit} second"
  end

  def transition(from:, to:, **attributes)
    moved = self.class.where(id: id, status: from)
      .update_all(attributes.merge(status: to, updated_at: Time.current)) == 1
    reload
    moved
  end

  def broadcast_status
    broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, :summary),
                               partial: "deploys/summary", locals: { deploy: self }
    app.broadcast_card
    app.broadcast_page
  end

  def app_ready_to_deploy
    reason = release_lock_kind? ? app&.release_lock_blocked_reason : app&.deploy_blocked_reason
    errors.add(:base, reason) if reason
  end

  def one_in_flight_per_app
    if app && Deploy.in_flight.where(app: app).where.not(id: id).exists?
      errors.add(:base, "#{app.name} already has a deploy in progress")
    end
  end
end
