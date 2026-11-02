require "test_helper"
require "mail_delivery"

class MailDeliveryTest < ActiveSupport::TestCase
  COMPLETE = { username: "MS_user", password: "not-a-real-password", from: "grateful-deploy@example.test" }.freeze

  test "MailerSend over SMTP once its username, password and From address are all set" do
    settings = MailDelivery.settings(COMPLETE)

    assert_equal :smtp, settings[:delivery_method]
    assert_equal "grateful-deploy@example.test", settings[:from]
    assert_equal({ address: "smtp.mailersend.net", port: 587, user_name: "MS_user", password: "not-a-real-password",
                   authentication: :plain, enable_starttls_auto: true }, settings[:smtp_settings])
  end

  test "letter_opener on this laptop until any of them is missing" do
    [ nil, {}, COMPLETE.except(:password), COMPLETE.merge(from: "") ].each do |mailersend|
      settings = MailDelivery.settings(mailersend)
      assert_equal :letter_opener, settings[:delivery_method], mailersend.inspect
      assert_equal "grateful-deploy@localhost", settings[:from]
      assert_nil settings[:smtp_settings]
    end
  end
end
