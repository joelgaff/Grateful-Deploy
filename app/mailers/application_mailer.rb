class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.configuration.x.mail_from || "grateful-deploy@localhost" }
  layout "mailer"
end
