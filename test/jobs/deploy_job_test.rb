require "test_helper"

class DeployJobTest < ActiveJob::TestCase
  setup do
    @app = apps(:storefront)
  end

  test "runs the deploy, saves the scrubbed log and marks it succeeded" do
    @app.update!(repo_path: build_fake_kamal_repo(<<~SH))
      echo "Building $*"
      echo "KAMAL_REGISTRY_PASSWORD=hunter2"
      echo "Finished all in 1.0 seconds"
    SH
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    deploy.reload
    assert deploy.succeeded?
    assert_equal 0, deploy.exit_code
    assert deploy.started_at && deploy.finished_at
    assert_equal "Building deploy -d nbg\nKAMAL_REGISTRY_PASSWORD=[FILTERED]\nFinished all in 1.0 seconds\n", deploy.log
  end

  test "a finished deploy, successful or not, checks status right away, so its own Kamal lock clears from the page" do
    [ "exit 0", "exit 1" ].each do |script|
      @app.update!(repo_path: build_fake_kamal_repo(script))
      deploy = @app.deploys.create!(kind: "deploy")

      assert_enqueued_with(job: RefreshStatusJob, args: [ { force: true } ]) { DeployJob.perform_now(deploy) }
    end
  end

  test "a deploy runs to the end and keeps its log even when every page redraw fails" do
    @app.update!(repo_path: build_fake_kamal_repo(%(echo one; echo two)))
    deploy = @app.deploys.create!(kind: "deploy")

    with_failing_broadcasts { DeployJob.perform_now(deploy) }

    assert deploy.reload.succeeded?
    assert_equal "one\ntwo\n", deploy.log
  end

  test "streams each line and the final status to the deploy's page" do
    @app.update!(repo_path: build_fake_kamal_repo("echo one\necho two"))
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    streams = capture_turbo_stream_broadcasts(deploy)
    appended = streams.select { |s| s["action"] == "append" }
    assert_equal [ "one", "two" ], appended.map { |s| s.at_css("template").text.strip }
    assert(streams.any? { |s| s["action"] == "replace" && s.to_html.include?("succeeded") })
  end

  test "a non-zero exit marks the deploy failed and keeps the exit code" do
    @app.update!(repo_path: build_fake_kamal_repo("echo nope\nexit 1"))
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    assert deploy.reload.failed?
    assert_equal 1, deploy.exit_code
  end

  test "a rollback passes its version to kamal" do
    @app.update!(repo_path: build_fake_kamal_repo('echo "$*"'))
    deploy = @app.deploys.create!(kind: "rollback", version: "7d1e0f2")

    DeployJob.perform_now(deploy)

    assert_equal "rollback 7d1e0f2 -d nbg\n", deploy.reload.log
  end

  test "an error before kamal starts still finishes the deploy as failed" do
    @app.update!(repo_path: "/nonexistent/grateful-deploy-test")
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    deploy.reload
    assert deploy.failed?
    assert_match "No such file or directory", deploy.log
    assert deploy.finished_at
  end

  test "updates the app's card when the deploy starts and finishes" do
    @app.update!(repo_path: build_fake_kamal_repo("echo ok"))
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    cards = capture_turbo_stream_broadcasts("apps")
    assert_equal 2, cards.size
    assert_includes cards.last.to_html, "succeeded"
  end

  test "a deploy canceled while queued never runs kamal" do
    marker = File.join(Dir.mktmpdir, "ran")
    @app.update!(repo_path: build_fake_kamal_repo("touch #{marker}"))
    deploy = @app.deploys.create!(kind: "deploy")
    deploy.cancel!

    DeployJob.perform_now(deploy)

    assert_not File.exist?(marker)
    assert deploy.reload.canceled?
  end

  test "records the process group so the deploy can be canceled" do
    @app.update!(repo_path: build_fake_kamal_repo("echo ok"))
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    assert deploy.reload.pid
  end

  test "a very long output line doesn't stop the deploy or the lines after it" do
    @app.update!(repo_path: build_fake_kamal_repo("echo before\nprintf 'a%.0s' $(seq 1 20000); echo @\necho after"))
    deploy = @app.deploys.create!(kind: "deploy")

    DeployJob.perform_now(deploy)

    deploy.reload
    assert deploy.succeeded?
    assert_equal "after", deploy.numbered_lines.last.first
  end

  test "cancel stops a running deploy and keeps it canceled" do
    @app.update!(repo_path: build_fake_kamal_repo("echo building\nsleep 30 & wait"))
    deploy = @app.deploys.create!(kind: "deploy")
    # Cancel once "building" is saved, so the test shows earlier output is kept.
    Thread.new do
      deadline = 5.seconds.from_now
      sleep 0.05 until Deploy.find(deploy.id).log.include?("building") || Time.current > deadline
      Deploy.find(deploy.id).cancel!
    end

    Timeout.timeout(10) { DeployJob.perform_now(deploy) }

    deploy.reload
    assert deploy.canceled?
    assert_match "building", deploy.log
    assert_match "Canceled from Grateful Deploy", deploy.log
  end

  test "a deploy over the time limit is stopped and marked failed" do
    @app.update!(repo_path: build_fake_kamal_repo("sleep 30 & wait"))
    deploy = @app.deploys.create!(kind: "deploy")
    limit = DeployJob.time_limit
    DeployJob.time_limit = 0.5

    Timeout.timeout(10) { DeployJob.perform_now(deploy) }

    deploy.reload
    assert deploy.failed?
    assert_match "Stopped after the 0.5 second time limit", deploy.log
  ensure
    DeployJob.time_limit = limit
  end
end
