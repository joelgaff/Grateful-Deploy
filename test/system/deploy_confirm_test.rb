require "application_system_test_case"

class DeployConfirmTest < ApplicationSystemTestCase
  setup do
    @repo = build_git_repo
    commit(@repo, "Ship the race map")
    @app = apps(:storefront)
    @app.update!(repo_path: @repo)
    sign_in
  end

  test "the Deploy confirm names the commit at the moment you click, not when the page loaded" do
    visit app_path(@app)
    sha = commit(@repo, "Fix the finish line")

    message = accept_confirm { click_button "Deploy" }

    assert_includes message, "Kamal will build #{sha.first(7)}"
    assert_text "waiting to start"
    deploy = @app.deploys.order(:created_at).last
    assert_current_path app_deploy_path(@app, deploy)
    assert_equal sha, deploy.git_sha
  end

  test "cancelling the confirm queues nothing" do
    visit app_path(@app)

    assert_no_difference -> { Deploy.count } do
      dismiss_confirm { click_button "Deploy" }
      assert_button "Deploy"
    end
  end

  test "a deploy started elsewhere while the confirm is open is refused, not run twice" do
    visit app_path(@app)
    click_button "Deploy"
    confirm = wait_for_confirm

    other = @app.start_deploy! # another tab, or a deploy-on-push
    confirm.accept

    # The page ends up telling the truth either way: the other deploy is in
    # progress and nothing else can start. Whether the refusal's message also
    # shows depends on which arrives first, the redirect or the live update
    # that replaced the confirmed form, so it isn't asserted.
    assert_button "Deploy in progress", disabled: true
    assert_selector ".rollbacks button[disabled]", minimum: 1
    assert_no_selector ".rollbacks button:not([disabled])"
    assert_equal [ other ], @app.deploys.in_flight.to_a
  end

  private

  def wait_for_confirm
    Selenium::WebDriver::Wait.new(timeout: Capybara.default_max_wait_time).until do
      page.driver.browser.switch_to.alert
    rescue Selenium::WebDriver::Error::NoSuchAlertError
      nil
    end
  end
end
