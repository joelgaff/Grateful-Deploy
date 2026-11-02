require "application_system_test_case"

# The app page's Logs panel. Jobs don't run in tests, so the test plays
# LogSessionJob: a throwaway `sleep` stands in for Kamal, and lines are
# appended the way the job appends them.
class AppLogsTest < ApplicationSystemTestCase
  setup do
    @app = apps(:storefront)
    sign_in
    visit app_path(@app)
    assert_selector "turbo-cable-stream-source[connected]", visible: false, count: 2
  end

  teardown { Process.kill("KILL", -@kamal) if @kamal && alive?(@kamal) }

  test "Follow live streams lines until Stop, which ends Kamal and keeps the lines" do
    page.execute_script("document.body.dataset.before = 'follow'")
    click_button "Follow live"
    # Follow live redirects back to this page; wait for that new page, so
    # lines don't land on the old one and vanish with it.
    assert_no_selector "body[data-before]", visible: false
    assert_selector "turbo-cable-stream-source[connected]", visible: false, count: 2
    assert_text "Waiting to start"
    session = @app.log_sessions.last
    @kamal = Process.spawn("sleep", "30", pgroup: true)

    session.started!(@kamal)
    assert_text "Following"
    %w[GET\ /races 200\ OK].each { session.append_line(it) }
    within("#logs_app_#{@app.id}") { assert_text "GET /races" }

    page.execute_script(<<~JS)
      document.body.dataset.before = "stop"
      document.addEventListener("turbo:submit-end", () => { window.stopAnswered = true }, { once: true })
    JS
    click_button "Stop"

    assert_button "Follow live"
    assert page.evaluate_async_script(<<~JS), "Stop's request never finished"
      const done = arguments[0], started = Date.now()
      const check = () => window.stopAnswered ? done(true) : Date.now() - started > 5000 ? done(false) : setTimeout(check, 50)
      check()
    JS
    assert_selector "body[data-before=stop]", visible: false # the same page, not reloaded
    within("#logs_app_#{@app.id}") { assert_text "200 OK" }
    assert session.reload.stopped?
    assert ended_within?(3.seconds, @kamal), "Stop didn't end Kamal"
  end

  test "the log stays pinned to the newest line, unless you scroll up to read" do
    session = @app.log_sessions.create!(mode: "follow")
    120.times { session.append_line("line #{it}") }
    assert_text "line 119"
    assert scrolled_to_bottom?

    page.execute_script("const log = document.getElementById('logs_app_#{@app.id}'); log.scrollTop = 0; log.dispatchEvent(new Event('scroll'))")
    session.append_line("line 120")
    assert_text "line 120"

    assert_equal 0, page.evaluate_script("document.getElementById('logs_app_#{@app.id}').scrollTop")
  end

  private

  def scrolled_to_bottom?
    page.evaluate_script(<<~JS)
      (() => { const log = document.getElementById("logs_app_#{@app.id}"); return log.scrollHeight - log.scrollTop - log.clientHeight < 2 })()
    JS
  end

  def ended_within?(limit, pid)
    deadline = limit.from_now
    until Process.waitpid(pid, Process::WNOHANG)
      return false if Time.current > deadline
      sleep 0.05
    end
    true
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
