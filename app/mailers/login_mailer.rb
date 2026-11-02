class LoginMailer < ApplicationMailer
  def code(identity, code)
    @code = code
    mail to: identity.email, subject: "Your login code: #{code}"
  end
end
