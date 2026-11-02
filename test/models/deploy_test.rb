require "test_helper"

class DeployTest < ActiveSupport::TestCase
  test "starts queued from the UI with an empty log" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    assert deploy.queued?
    assert deploy.ui?
    assert_equal "", deploy.log
  end

  test "a rollback needs a git sha to roll back to" do
    assert_not apps(:storefront).deploys.new(kind: "rollback").valid?
    assert_not apps(:storefront).deploys.new(kind: "rollback", version: "nope").valid?
    assert apps(:storefront).deploys.new(kind: "rollback", version: "7d1e0f2").valid?
  end

  test "only one queued or running deploy per app" do
    apps(:storefront).deploys.create!(kind: "deploy")

    second = apps(:storefront).deploys.new(kind: "deploy")
    assert_not second.valid?
    assert_includes second.errors[:base], "storefront already has a deploy in progress"
    assert apps(:incidents).deploys.new(kind: "deploy").valid?
  end

  test "the database enforces the lock even when validations are skipped" do
    apps(:storefront).deploys.create!(kind: "deploy")

    assert_raises(ActiveRecord::RecordNotUnique) do
      apps(:storefront).deploys.new(kind: "deploy").save!(validate: false)
    end
  end

  test "a finished deploy frees the lock" do
    apps(:storefront).deploys.create!(kind: "deploy", status: "failed")

    assert apps(:storefront).deploys.new(kind: "deploy").valid?
  end

  test "duration once finished" do
    assert_equal 3.minutes, deploys(:storefront_done).duration
    assert_nil apps(:storefront).deploys.new.duration
  end

  test "fail_abandoned! fails running deploys left by a dead worker and frees the lock" do
    freeze_time do
      kamal = Process.spawn("sh", "-c", "sleep 30 & wait", pgroup: true)
      running = apps(:storefront).deploys.create!(kind: "deploy", status: "running", started_at: 5.minutes.ago, pid: kamal)
      queued = apps(:incidents).deploys.create!(kind: "deploy")

      Deploy.fail_abandoned!

      running.reload
      assert running.failed?
      assert_equal Time.current, running.finished_at
      assert_match "Grateful Deploy restarted", running.log
      assert queued.reload.queued?
      assert apps(:storefront).deploys.new(kind: "deploy").valid?
      Timeout.timeout(5) { Process.wait(kamal) }
    end
  end

  test "append_line masks secrets before storing or broadcasting, whatever the source" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    deploy.append_line("password=hunter2")
    deploy.finish!(0)

    assert_equal "password=[FILTERED]\n", deploy.reload.log
    assert(capture_turbo_stream_broadcasts(deploy).none? { it.to_html.include?("hunter2") })
  end

  test "rescrub_logs! re-masks saved logs with the current rules" do
    deploy = deploys(:storefront_done)
    deploy.update_column(:log, "ok\nAuthorization: Bearer hunter2\n")

    Deploy.rescrub_logs!

    assert_equal "ok\nAuthorization: Bearer [FILTERED]\n", deploy.reload.log
  end

  test "each line is saved the moment it arrives, numbered in order" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    assert_equal 1, deploy.append_line("Building")
    assert_equal "Building\n", Deploy.find(deploy.id).log
    assert_equal 2, deploy.append_line("Pushing")
    assert_equal "Building\nPushing\n", Deploy.find(deploy.id).log
  end

  test "lines written from two processes (the job and a Cancel) keep their own numbers" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")
    other = Deploy.find(deploy.id)

    deploy.append_line("one")
    other.append_line("two")
    deploy.append_line("three")

    assert_equal "one\ntwo\nthree\n", deploy.reload.log
    assert_equal 3, deploy.log_lines
  end

  test "multi-line text (an error message) becomes one numbered line each, so numbers match the saved log" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")
    deploy.append_line("one")

    assert_equal 3, deploy.append_line("grateful-deploy: Error: first\nsecond")
    assert_equal 4, deploy.append_line("four")

    assert_equal [ [ "grateful-deploy: Error: first", 2 ], [ "second", 3 ], [ "four", 4 ] ], deploy.reload.numbered_lines(after: 1)
    assert_equal 4, deploy.log_lines
    assert_equal %w[1 2 3 4], capture_turbo_stream_broadcasts(deploy).flat_map { it.css("template .log-line").map { it["data-line"] } }
  end

  test "a streamed line carries its number" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")
    deploy.append_line("Building")

    line = capture_turbo_stream_broadcasts(deploy).last.at_css("template .log-line")
    assert_equal "deploy_#{deploy.id}_line_1", line["id"]
    assert_equal "1", line["data-line"]
  end
end
