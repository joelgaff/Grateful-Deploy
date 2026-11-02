require "test_helper"

class LogSessionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:owner)
    @app = apps(:storefront)
  end

  test "last 200 lines starts a recent log session" do
    assert_enqueued_with(job: LogSessionJob) do
      post app_log_sessions_path(@app), params: { mode: "recent" }
    end

    assert @app.log_sessions.last.recent_mode?
    assert_redirected_to app_path(@app, anchor: "logs")
  end

  test "follow starts a follow session" do
    post app_log_sessions_path(@app), params: { mode: "follow" }

    assert @app.log_sessions.last.follow_mode?
  end

  test "an unknown mode falls back to recent" do
    post app_log_sessions_path(@app), params: { mode: "exec" }

    assert @app.log_sessions.last.recent_mode?
  end

  test "refuses a second session while one is running" do
    @app.log_sessions.create!(mode: "follow")

    assert_no_difference -> { LogSession.count } do
      post app_log_sessions_path(@app), params: { mode: "recent" }
    end
    assert_equal "storefront is already showing logs", flash[:alert]
  end

  test "stop ends a running session" do
    session = @app.log_sessions.create!(mode: "follow")

    delete app_log_session_path(@app, session)

    assert session.reload.stopped?
    assert_redirected_to app_path(@app, anchor: "logs")
  end

  test "the app page shows log buttons, or stop while following" do
    get app_path(@app)
    assert_select "#log_controls_app_#{@app.id} button", "Last 200 lines"
    assert_select "#log_controls_app_#{@app.id} button", "Follow live"

    session = @app.log_sessions.create!(mode: "follow")
    get app_path(@app)
    assert_select "#log_controls_app_#{@app.id} form[action=?] button", app_log_session_path(@app, session), text: "Stop"
  end

  test "controls update live when a session changes status" do
    session = @app.log_sessions.create!(mode: "follow")

    session.finish_as("finished")

    controls = capture_turbo_stream_broadcasts([ @app, :logs ]).select { it["target"] == "log_controls_app_#{@app.id}" }
    assert_includes controls.last.to_html, "Follow live"
  end

  test "stop from the page keeps the streamed lines on screen" do
    session = @app.log_sessions.create!(mode: "follow")

    delete app_log_session_path(@app, session), as: :turbo_stream

    assert_response :no_content
    assert session.reload.stopped?
  end

  test "a session the job hasn't started yet says it is waiting" do
    @app.log_sessions.create!(mode: "follow")

    get app_path(@app)

    assert_select "#log_controls_app_#{@app.id} .status", "Waiting to start"
  end

  test "once started the controls say following" do
    @app.log_sessions.create!(mode: "follow", pid: 4242)

    get app_path(@app)

    assert_select "#log_controls_app_#{@app.id} .status", "Following"
  end
end
