require "test_helper"

# Kamal's post-deploy hook in each app repo reports deploys made outside
# Grateful Deploy (a terminal, CI) so history and the rollback list stay complete.
class KamalHooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SHA = "3f82b485b194940a926be0ddfdd830458db0c220".freeze

  setup do
    @path = HookToken.path
    @dir = Dir.mktmpdir
    HookToken.path = File.join(@dir, "hook_token")
    File.write(HookToken.path, "hook-secret\n")
  end

  teardown do
    HookToken.path = @path
    FileUtils.rm_rf(@dir)
  end

  def report(token: "hook-secret", **kamal)
    params = { service: "storefront", destination: "nbg", version: SHA, command: "deploy", runtime: "42" }.merge(kamal)
    post kamal_hooks_post_deploy_path, params: params, headers: token ? { "Authorization" => "Bearer #{token}" } : {}
  end

  test "records a terminal deploy as succeeded, outside Grateful Deploy, and checks status" do
    freeze_time do
      assert_enqueued_with(job: RefreshStatusJob, args: [ { force: true } ]) { report }

      assert_response :created
      deploy = apps(:storefront).deploys.outside.sole
      assert deploy.deploy_kind?
      assert deploy.succeeded?
      assert deploy.outside?
      assert_equal SHA, deploy.git_sha
      assert_equal 42.seconds.ago, deploy.started_at
      assert_equal Time.current, deploy.finished_at
      assert_equal "Deployed outside Grateful Deploy (kamal deploy). Its output isn't recorded here.\n", deploy.log
    end
  end

  test "a rollback is recorded as one, and the version joins the rollback list" do
    report(command: "rollback")

    deploy = apps(:storefront).deploys.outside.sole
    assert deploy.rollback_kind?
    assert_equal SHA, deploy.version
  end

  test "an app without a destination is found by its service alone" do
    report(service: "incidents", destination: "")

    assert_response :created
    assert apps(:incidents).deploys.outside.one?
  end

  test "a version with uncommitted changes is recorded but never offered for rollback" do
    report(version: "#{SHA}_uncommitted_9f2e")

    deploy = apps(:storefront).deploys.outside.sole
    assert_nil deploy.git_sha
    assert_includes deploy.log, "#{SHA.first(7)} with uncommitted changes"
    assert_not_includes apps(:storefront).rollback_versions, "#{SHA}_uncommitted_9f2e"
  end

  test "Grateful Deploy's own deploy reports through the same hook, and is ignored" do
    apps(:storefront).deploys.create!(kind: "deploy").tap(&:start!)

    assert_no_difference -> { Deploy.count } do
      report
    end
    assert_response :ok
  end

  test "is recorded even while Kamal's lock is held or a kamal_env value is missing" do
    servers(:nbg).server_snapshots.create!(checked_at: Time.current, kamal_locks: { "lock-storefront-nbg" => "Locked by: x" })
    apps(:storefront).update!(kamal_env: { "STOREFRONT_DOMAIN" => nil })

    assert_difference -> { Deploy.count } do
      report
    end
  end

  test "a wrong or missing token is refused, with nothing recorded" do
    assert_no_difference -> { Deploy.count } do
      report(token: "wrong")
      assert_response :unauthorized
      report(token: nil)
      assert_response :unauthorized
    end
  end

  test "an app Grateful Deploy doesn't know is a 404, with nothing recorded" do
    assert_no_difference -> { Deploy.count } do
      report(service: "somebody-else")
    end
    assert_response :not_found
  end
end
