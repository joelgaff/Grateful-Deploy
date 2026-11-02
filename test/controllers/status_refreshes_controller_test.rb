require "test_helper"

class StatusRefreshesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "refresh now queues a status refresh and returns to the apps page" do
    sign_in_as users(:owner)

    assert_enqueued_with(job: RefreshStatusJob, args: [ { force: true } ]) { post status_refresh_path }
    assert_redirected_to root_path
  end

  test "the apps page has the refresh button" do
    sign_in_as users(:owner)
    get root_path

    assert_select "form[action=?] button", status_refresh_path, text: "Refresh now"
  end

  test "refresh now returns to the page it was pressed on" do
    sign_in_as users(:owner)

    post status_refresh_path, headers: { "HTTP_REFERER" => servers_url }

    assert_redirected_to servers_url
  end
end
