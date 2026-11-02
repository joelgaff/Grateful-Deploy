# Signs in through the real magic-link flow: issue a code, confirm it.
module SessionTestHelper
  def sign_in_as(user)
    code = user.identity.issue_login_code!
    post confirm_session_path(identity_id: user.identity.id), params: { code: code }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) { include SessionTestHelper }
