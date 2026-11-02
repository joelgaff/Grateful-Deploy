require "test_helper"

class RollbacksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  OFFERED = "7d1e0f2a9c4b5e6f708192a3b4c5d6e7f8091a2b".freeze

  setup { sign_in_as users(:owner) }

  test "rolls back to an offered version" do
    assert_enqueued_with(job: DeployJob) do
      post app_rollbacks_path(apps(:storefront)), params: { version: OFFERED }
    end

    deploy = apps(:storefront).deploys.order(:created_at).last
    assert deploy.rollback_kind?
    assert_equal OFFERED, deploy.version
    assert_redirected_to app_deploy_path(apps(:storefront), deploy)
  end

  test "refuses a version that was not offered, even a well-formed sha" do
    assert_no_difference -> { Deploy.count } do
      post app_rollbacks_path(apps(:storefront)), params: { version: "a" * 40 }
    end
    assert_redirected_to app_path(apps(:storefront))
    assert_equal "That version isn't one storefront can roll back to.", flash[:alert]
  end

  test "refuses while a deploy is in flight" do
    apps(:storefront).deploys.create!(kind: "deploy")

    assert_no_difference -> { Deploy.count } do
      post app_rollbacks_path(apps(:storefront)), params: { version: OFFERED }
    end
    assert_equal "storefront already has a deploy in progress", flash[:alert]
  end

  test "the app page offers a confirmed rollback button per version" do
    get app_path(apps(:storefront))

    assert_select ".rollbacks form[action=?]", app_rollbacks_path(apps(:storefront)), 2
    assert_select ".rollbacks form input[name=version][value=?]", OFFERED
    assert_select ".rollbacks button[data-turbo-confirm]", "Roll back to 7d1e0f2"
  end

  test "the app page explains when there is nothing to roll back to" do
    get app_path(apps(:incidents))

    assert_select ".rollbacks", /No earlier versions known yet/
  end
end
