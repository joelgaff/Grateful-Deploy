require "test_helper"

class DeploysControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:owner) }

  test "deploy queues a deploy for the app" do
    assert_difference -> { apps(:storefront).deploys.count }, 1 do
      assert_enqueued_with(job: DeployJob) { post app_deploys_path(apps(:storefront)) }
    end

    deploy = apps(:storefront).deploys.order(:created_at).last
    assert deploy.deploy_kind?
    assert deploy.ui?
    assert_redirected_to app_deploy_path(apps(:storefront), deploy)
  end

  test "a second deploy while one is in flight is refused" do
    apps(:storefront).deploys.create!(kind: "deploy")

    assert_no_difference -> { Deploy.count } do
      post app_deploys_path(apps(:storefront))
    end
    assert_redirected_to app_path(apps(:storefront))
    assert_equal "storefront already has a deploy in progress", flash[:alert]
  end

  test "cannot deploy another organization's app" do
    stranger = Organization.create!(name: "Other").servers.create!(name: "x", host: "198.51.100.9")
                           .apps.create!(name: "x", repo_path: "/tmp/x", service: "x", destination: "x")

    assert_no_difference -> { Deploy.count } do
      post app_deploys_path(stranger)
    end
    assert_response :not_found
  end

  test "the app page has a confirmed deploy button" do
    get app_path(apps(:storefront))

    assert_select "form[action=?] button[data-turbo-confirm]", app_deploys_path(apps(:storefront)), text: "Deploy"
  end

  test "the deploy button is disabled while a deploy is in flight" do
    apps(:storefront).deploys.create!(kind: "deploy")

    get app_path(apps(:storefront))

    assert_select "button[disabled]", "Deploy in progress"
  end

  test "deploy page shows the saved log, status and commit, and subscribes for live lines" do
    deploy = deploys(:storefront_done)

    get app_deploy_path(apps(:storefront), deploy)

    assert_response :success
    assert_select "#status_deploy_#{deploy.id}", "succeeded"
    assert_select "#log_deploy_#{deploy.id} .log-line", "Finished all in 180.2 seconds"
    assert_select ".deploy-facts", /7d1e0f2/
    assert_select ".deploy-facts", /Tighten race list layout/
    assert_select "turbo-cable-stream-source"
  end

  test "deploy page shows when it was queued in the same exact format as everywhere else" do
    deploy = deploys(:storefront_done)
    deploy.update_column(:created_at, Time.zone.local(2026, 10, 15, 17, 3))

    get app_deploy_path(apps(:storefront), deploy)

    assert_select ".deploy-facts dd", "Oct 15, 17:03"
  end

  test "a deploy is only found through its own app" do
    get app_deploy_path(apps(:incidents), deploys(:storefront_done))

    assert_response :not_found
  end

  test "a queued deploy says it is waiting to start" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    get app_deploy_path(apps(:storefront), deploy)

    assert_select "#status_deploy_#{deploy.id}.status--queued", "waiting to start"
  end

  test "the saved log's lines carry their numbers" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy", status: "succeeded", log: "one\ntwo\n", log_lines: 2)
    sign_in_as users(:owner)

    get app_deploy_path(deploy.app, deploy)

    assert_select "#log_deploy_#{deploy.id} .log-line[data-line]", 2
    assert_select "#deploy_#{deploy.id}_line_2", "two"
  end

  test "the deploy and rollback buttons are disabled with the reason while a kamal_env value isn't set yet" do
    apps(:storefront).update!(kamal_env: { "STOREFRONT_DOMAIN" => nil })

    get app_path(apps(:storefront))

    assert_select "button[disabled]", "Deploy"
    assert_select ".deploy-blocked", "Set STOREFRONT_DOMAIN in config/fleet.yml before deploying storefront."
    assert_select ".rollbacks button[disabled]", minimum: 1
    assert_select ".rollbacks button:not([disabled])", false
  end
end
