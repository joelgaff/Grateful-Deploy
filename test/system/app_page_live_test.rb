require "application_system_test_case"

class AppPageLiveTest < ApplicationSystemTestCase
  setup do
    @repo = build_git_repo
    commit(@repo, "Ship the race map")
    @app = apps(:storefront)
    @app.update!(repo_path: @repo)
    sign_in
  end

  test "coming back to the tab shows a commit made since the page loaded" do
    visit app_path(@app)
    sha = commit(@repo, "Fix the finish line")
    assert_no_text sha.first(7)

    page.execute_script("window.dispatchEvent(new Event('focus'))")

    within("#deploy_controls_app_#{@app.id}") { assert_text sha.first(7) }
  end

  test "switching back to the tab refreshes at most once every 10 seconds" do
    visit app_path(@app)
    page.execute_script(<<~JS)
      window.refreshes = 0
      const fetch = window.fetch
      window.fetch = (url, ...rest) => { if (String(url).includes("ship_preview")) window.refreshes++; return fetch(url, ...rest) }
    JS

    3.times { page.execute_script("window.dispatchEvent(new Event('focus'))") }

    assert_equal 1, page.evaluate_script("window.refreshes")
  end

  test "a deploy queued elsewhere turns the button into Deploy in progress, no reload" do
    visit app_path(@app)
    assert_button "Deploy"

    @app.start_deploy!

    assert_button "Deploy in progress", disabled: true
    within("#deploy_history_app_#{@app.id}") { assert_text "waiting to start" }
  end
end
