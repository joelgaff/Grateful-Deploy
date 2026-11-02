require "test_helper"

# Browser tests in headless Chromium. They use the system's Chromium and
# chromedriver, so Selenium never downloads a browser, and they switch Action
# Cable to the in-process async adapter so broadcasts reach the page (the
# other tests keep the test adapter, which only records them).
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  CHROMIUM = "/usr/bin/chromium".freeze
  CHROMEDRIVER = "/usr/bin/chromedriver".freeze

  Selenium::WebDriver::Chrome::Service.driver_path = CHROMEDRIVER
  # If Selenium Manager ever runs anyway, it stays offline and sends no stats.
  ENV["SE_OFFLINE"] = "true"
  ENV["SE_AVOID_STATS"] = "true"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.binary = CHROMIUM
  end

  # Outside tmp/, which bin/setup (the first bin/ci step) clears, so a flaky
  # failure's screenshot survives the next run.
  Capybara.save_path = Rails.root.join("log/screenshots").to_s

  setup { use_cable_adapter("async") }
  teardown { use_cable_adapter("test") }

  def sign_in(user = users(:owner))
    code = user.identity.issue_login_code!
    visit verify_session_path(identity_id: user.identity.id)
    fill_in "code", with: code
    click_button "Sign in"
    assert_text "Signed in."
  end

  private

  def use_cable_adapter(name)
    ActionCable.server.config.cable = { "adapter" => name }
    ActionCable.server.restart
  end
end
