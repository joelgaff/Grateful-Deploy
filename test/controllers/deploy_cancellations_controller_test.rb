require "test_helper"

class DeployCancellationsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:owner) }

  test "cancels an in-flight deploy" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    post app_deploy_cancellation_path(apps(:storefront), deploy)

    assert deploy.reload.canceled?
    assert_redirected_to app_deploy_path(apps(:storefront), deploy)
  end

  test "a finished deploy can't be canceled" do
    deploy = deploys(:storefront_done)

    post app_deploy_cancellation_path(apps(:storefront), deploy)

    assert deploy.reload.succeeded?
    assert_equal "This deploy already finished.", flash[:alert]
  end

  test "a deploy is only canceled through its own app" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    post app_deploy_cancellation_path(apps(:incidents), deploy)

    assert_response :not_found
    assert deploy.reload.queued?
  end

  test "the deploy page offers a confirmed cancel while in flight" do
    deploy = apps(:storefront).deploys.create!(kind: "deploy")

    get app_deploy_path(apps(:storefront), deploy)

    assert_select "form[action=?] button[data-turbo-confirm]", app_deploy_cancellation_path(apps(:storefront), deploy), text: "Cancel deploy"
  end

  test "no cancel button once finished" do
    get app_deploy_path(apps(:storefront), deploys(:storefront_done))

    assert_select "button", text: "Cancel deploy", count: 0
  end
end
