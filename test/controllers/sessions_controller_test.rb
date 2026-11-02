require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "signing out says Fare thee well" do
    sign_in_as users(:owner)
    delete session_path

    assert_redirected_to new_session_path
    assert_equal "Fare thee well.", flash[:notice]
  end
end
