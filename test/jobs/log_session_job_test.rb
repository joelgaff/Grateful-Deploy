require "test_helper"

class LogSessionJobTest < ActiveJob::TestCase
  setup { @app = apps(:storefront) }

  test "recent mode streams the last 200 lines and finishes" do
    @app.update!(repo_path: build_fake_kamal_repo('echo "$*"; echo "RAILS_MASTER_KEY=secret"'))
    session = @app.log_sessions.create!(mode: "recent")

    LogSessionJob.perform_now(session)

    lines = capture_turbo_stream_broadcasts([ @app, :logs ]).select { it["action"] == "append" }.map { it.at_css("template").text.strip }
    assert_equal [ "app logs -n 200 --skip-hooks -d nbg", "RAILS_MASTER_KEY=[FILTERED]" ], lines
    assert session.reload.finished?
    assert session.pid
  end

  test "follow mode runs until stopped" do
    @app.update!(repo_path: build_fake_kamal_repo("echo following\nsleep 30 & wait"))
    session = @app.log_sessions.create!(mode: "follow")
    Thread.new { sleep 0.2 until LogSession.find(session.id).pid; LogSession.find(session.id).stop! }

    Timeout.timeout(10) { LogSessionJob.perform_now(session) }

    assert session.reload.stopped?
  end

  test "follow mode stops itself after the time limit" do
    @app.update!(repo_path: build_fake_kamal_repo("sleep 30 & wait"))
    session = @app.log_sessions.create!(mode: "follow")

    limit = LogSessionJob.follow_limit
    LogSessionJob.follow_limit = 0.5
    Timeout.timeout(10) { LogSessionJob.perform_now(session) }

    assert session.reload.stopped?
  ensure
    LogSessionJob.follow_limit = limit
  end

  test "a session stopped while waiting to start never runs Kamal" do
    marker = Rails.root.join("tmp/kamal-ran-#{SecureRandom.hex(4)}")
    @app.update!(repo_path: build_fake_kamal_repo("touch #{marker}; sleep 30 & wait"))
    session = @app.log_sessions.create!(mode: "follow")
    session.stop!

    Timeout.timeout(10) { LogSessionJob.perform_now(session) }

    assert_not File.exist?(marker), "Kamal ran for a stopped session"
    assert session.reload.stopped?
  ensure
    FileUtils.rm_f(marker)
  end

  test "a failing command marks the session failed" do
    @app.update!(repo_path: build_fake_kamal_repo("echo boom; exit 1"))
    session = @app.log_sessions.create!

    LogSessionJob.perform_now(session)

    assert session.reload.failed?
  end
end
