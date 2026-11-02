require "test_helper"

class DeployTransitionsTest < ActiveSupport::TestCase
  setup { @deploy = apps(:storefront).deploys.create!(kind: "deploy") }

  test "start! moves a queued deploy to running" do
    assert @deploy.start!
    assert @deploy.reload.running?
    assert @deploy.started_at
  end

  test "start! refuses a deploy that is no longer queued" do
    @deploy.cancel!

    assert_not @deploy.start!
    assert @deploy.reload.canceled?
  end

  test "the first final status wins" do
    @deploy.start!
    job_copy = Deploy.find(@deploy.id)

    @deploy.cancel!

    assert_not job_copy.finish!(0)
    assert job_copy.canceled?
  end

  test "finish! records success, exit code and time once" do
    @deploy.start!

    assert @deploy.finish!(0)
    assert @deploy.succeeded?
    assert_equal 0, @deploy.exit_code
    assert @deploy.finished_at
    assert_not @deploy.finish!(1)
    assert @deploy.reload.succeeded?
  end

  test "a canceled deploy frees the app's lock" do
    @deploy.cancel!

    assert apps(:storefront).deploys.new(kind: "deploy").valid?
  end

  test "Cancel stops Kamal even when redrawing the page fails" do
    pid = Process.spawn("sh", "-c", "sleep 30 & wait", pgroup: true)
    @deploy.start!
    @deploy.update_column(:pid, pid)

    with_failing_broadcasts { @deploy.cancel! }

    Timeout.timeout(15) { Process.wait(pid) }
    assert @deploy.reload.canceled?
  end

  def broadcast_summary
    capture_turbo_stream_broadcasts(@deploy).select { it["target"] == "summary_deploy_#{@deploy.id}" }.last&.to_html
  end

  test "finishing updates the deploy page: Took and exit code appear, Cancel goes" do
    @deploy.start!
    assert_includes broadcast_summary, "Cancel deploy"

    @deploy.finish!(0)

    summary = broadcast_summary
    assert_includes summary, "Took"
    assert_includes summary, "Exit code"
    assert_not_includes summary, "Cancel deploy"
  end
end
