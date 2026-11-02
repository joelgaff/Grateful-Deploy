# How production sends mail (login codes). MailerSend over SMTP once its
# username, password and From address are all in the credentials
# (bin/rails credentials:edit, under mailersend:); until then letter_opener,
# which opens each email in the browser on this laptop, as in development.
# Required by config/environments/production.rb before the app loads.
module MailDelivery
  LOCAL_FROM = "grateful-deploy@localhost".freeze

  def self.settings(mailersend)
    mailersend = (mailersend || {}).to_h.symbolize_keys

    if %i[username password from].all? { mailersend[it].present? }
      { delivery_method: :smtp, from: mailersend[:from],
        smtp_settings: { address: "smtp.mailersend.net", port: 587, user_name: mailersend[:username],
                         password: mailersend[:password], authentication: :plain, enable_starttls_auto: true } }
    else
      { delivery_method: :letter_opener, from: LOCAL_FROM }
    end
  end
end
