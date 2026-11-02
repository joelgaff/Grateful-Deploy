require "test_helper"

class AppStartDeployTest < ActiveJob::TestCase
  setup do
    @repo = build_git_repo
    @sha = commit(@repo, "Ship the race map")
    @app = apps(:storefront)
    @app.update!(repo_path: @repo)
  end

  test "records the repo's HEAD commit and queues the job" do
    deploy = @app.start_deploy!

    assert_enqueued_with job: DeployJob, args: [ deploy ]

    assert deploy.deploy_kind?
    assert deploy.queued?
    assert_equal @sha, deploy.git_sha
    assert_equal "main", deploy.git_branch
    assert_equal "Ship the race map", deploy.git_message
  end

  test "a rollback keeps its target version" do
    deploy = @app.start_deploy!(kind: "rollback", version: "7d1e0f2")

    assert deploy.rollback_kind?
    assert_equal "7d1e0f2", deploy.version
  end

  test "refuses to queue a second deploy while one is in flight" do
    @app.start_deploy!

    assert_no_enqueued_jobs do
      assert_raises(ActiveRecord::RecordInvalid) { @app.start_deploy! }
    end
  end

  test "refuses to deploy or roll back while a kamal_env value isn't set yet" do
    @app.update!(kamal_env: { "STOREFRONT_SERVER" => "203.0.113.30", "STOREFRONT_DOMAIN" => nil })

    assert_no_enqueued_jobs do
      [ {}, { kind: "rollback", version: "7d1e0f2" } ].each do |options|
        error = assert_raises(ActiveRecord::RecordInvalid) { @app.start_deploy!(**options) }
        assert_includes error.record.errors[:base], "Set STOREFRONT_DOMAIN in config/fleet.yml before deploying storefront"
      end
    end
  end
end
