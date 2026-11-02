require "test_helper"

# Stop container and Start container on an app's page.
class ContainerButtonsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  STOPPED = "a7227ad0c1e2b3f4a5b6c7d8e9f0a1b2c3d4e5f6".freeze

  setup { sign_in_as users(:owner) }

  def snapshot(app, state)
    app.status_snapshots.create!(container_state: state, version: STOPPED, checked_at: Time.current,
                                 health_code: (200 if state == "running"))
  end

  test "a running app offers a confirmed Stop, which queues kamal app stop" do
    snapshot(apps(:storefront), "running")

    get app_path(apps(:storefront))
    assert_select "form[action=?] button[data-turbo-confirm*=?]", app_stops_path(apps(:storefront)), "data stays", text: "Stop container"
    assert_select "form[action=?]", app_starts_path(apps(:storefront)), false

    assert_enqueued_with(job: DeployJob) { post app_stops_path(apps(:storefront)) }
    deploy = apps(:storefront).deploys.order(:created_at).last
    assert deploy.stop_kind?
    assert_redirected_to app_deploy_path(apps(:storefront), deploy)
  end

  test "a stopped app shows Stopped, not Down, and offers Start for the stopped version" do
    snapshot(apps(:storefront), "exited")

    get root_path
    assert_select "#card_app_#{apps(:storefront).id} .health--stopped", "Stopped"

    get app_path(apps(:storefront))
    assert_select "form[action=?]", app_stops_path(apps(:storefront)), false
    assert_select "form[action=?] button", app_starts_path(apps(:storefront)), text: "Start container"

    assert_enqueued_with(job: DeployJob) { post app_starts_path(apps(:storefront)) }
    deploy = apps(:storefront).deploys.order(:created_at).last
    assert deploy.start_kind?
    assert_equal STOPPED, deploy.version
  end

  test "Stop is refused unless the app is running, Start unless it's stopped" do
    assert_no_enqueued_jobs do
      post app_stops_path(apps(:incidents)) # fixture: restarting
      assert_equal "incidents isn't running.", flash[:alert]
      post app_starts_path(apps(:storefront)) # fixture: running
      assert_equal "storefront isn't stopped.", flash[:alert]
    end
  end

  test "the buttons are off while a deploy runs" do
    apps(:storefront).deploys.create!(kind: "deploy", status: "running")

    get app_path(apps(:storefront))
    assert_select "form[action=?] button[disabled]", app_stops_path(apps(:storefront)), text: "Stop container"
  end
end
