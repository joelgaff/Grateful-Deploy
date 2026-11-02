require "test_helper"

class LogSessionTest < ActiveSupport::TestCase
  setup { @app = apps(:storefront) }

  test "starts running in recent mode by default" do
    session = @app.log_sessions.create!

    assert session.running?
    assert session.recent_mode?
  end

  test "one running log session per app" do
    @app.log_sessions.create!(mode: "follow")

    assert_not @app.log_sessions.new(mode: "recent").valid?
    assert_raises(ActiveRecord::RecordNotUnique) { @app.log_sessions.new.save!(validate: false) }
    assert apps(:incidents).log_sessions.new.valid?
  end

  test "stop! ends the whole process group and marks it stopped" do
    pid = Process.spawn("sh", "-c", "sleep 30 & wait", pgroup: true)
    session = @app.log_sessions.create!(mode: "follow", pid: pid)

    session.stop!

    Timeout.timeout(5) { Process.wait(pid) }
    assert session.reload.stopped?
    assert session.finished_at
  end

  test "stop! on an exited process just marks it stopped" do
    session = @app.log_sessions.create!(mode: "follow", pid: 999_999_999)

    session.stop!

    assert session.reload.stopped?
  end

  test "lines are broadcast to the app's log panel" do
    session = @app.log_sessions.create!

    session.append_line("GET /up 200")

    streams = capture_turbo_stream_broadcasts([ @app, :logs ])
    assert_equal "append", streams.last["action"]
    assert_equal "logs_app_#{@app.id}", streams.last["target"]
    assert_includes streams.last.to_html, "GET /up 200"
  end

  test "stop_abandoned! stops sessions left running by a restart, including their processes" do
    pid = Process.spawn("sh", "-c", "sleep 30 & wait", pgroup: true)
    session = @app.log_sessions.create!(mode: "follow", pid: pid)

    LogSession.stop_abandoned!

    Timeout.timeout(5) { Process.wait(pid) }
    assert session.reload.stopped?
  end

  test "the first final status wins: a job finishing after a stop keeps it stopped" do
    session = @app.log_sessions.create!(mode: "follow")
    job_copy = LogSession.find(session.id) # loaded while still running

    session.stop!

    assert_not job_copy.finish_as("failed")
    assert job_copy.stopped?
    assert session.reload.stopped?
  end

  test "finish_as moves a running session to its final status once" do
    session = @app.log_sessions.create!

    assert session.finish_as("finished")
    assert session.finished?
    assert session.finished_at
    assert_not session.finish_as("failed")
    assert session.reload.finished?
  end

  test "append_line masks secrets before broadcasting, whatever the source" do
    @app.log_sessions.create!.append_line("Authorization: Bearer hunter2")

    assert(capture_turbo_stream_broadcasts([ @app, :logs ]).none? { it.to_html.include?("hunter2") })
  end

  test "started! records the pid and updates the controls live" do
    session = @app.log_sessions.create!(mode: "follow")

    session.started!(4242)

    assert_equal 4242, session.reload.pid
    controls = capture_turbo_stream_broadcasts([ @app, :logs ]).select { it["target"] == "log_controls_app_#{@app.id}" }
    assert_includes controls.last.to_html, "Following"
  end

  test "started! on a session stopped before Kamal launched ends that process" do
    session = @app.log_sessions.create!(mode: "follow")
    session.stop!
    pid = Process.spawn("sh", "-c", "sleep 30 & wait", pgroup: true)

    assert_not session.started!(pid)

    Timeout.timeout(5) { Process.wait(pid) }
    assert session.reload.stopped?
  end

  test "stop! ends a process that started after the session was loaded" do
    session = @app.log_sessions.create!(mode: "follow")
    pid = Process.spawn("sh", "-c", "sleep 30 & wait", pgroup: true)
    LogSession.find(session.id).started!(pid)

    session.stop!

    Timeout.timeout(5) { Process.wait(pid) }
    assert session.reload.stopped?
  end
end
