require "test_helper"

# The line next to Deploy saying what a deploy would ship, and the same facts
# in the confirm dialog.
class AppShipPreviewTest < ActionDispatch::IntegrationTest
  setup do
    @repo = build_git_repo
    @running = commit(@repo, "Running now")
    @app = apps(:storefront)
    @app.update!(repo_path: @repo)
    @app.status_snapshots.create!(version: @running, container_state: "running", checked_at: Time.current)
    sign_in_as users(:owner)
  end

  def ship_line
    get app_path(@app)
    css_select(".ship-preview").first&.text&.squish
  end

  def deploy_confirm
    get app_path(@app)
    css_select("form[action='#{app_deploys_path(@app)}'] [data-turbo-confirm]").first["data-turbo-confirm"]
  end

  test "shows HEAD and how far it is ahead of the running version" do
    commit(@repo, "Two")
    head = commit(@repo, "Three")

    assert_equal "HEAD #{head.first(7)} · 2 commits ahead of running · no local CI", ship_line
  end

  test "says when HEAD is what's already running" do
    assert_equal "HEAD #{@running.first(7)} · same as running · no local CI", ship_line
  end

  test "warns about uncommitted changes, which don't ship" do
    File.write(File.join(@repo, "about.html.erb"), "new page")

    assert_equal "HEAD #{@running.first(7)} · same as running · uncommitted changes · no local CI", ship_line
  end

  test "warns when HEAD is behind the running version" do
    git(@repo, "reset", "-q", "--hard", "#{@running}~1")

    assert_equal "HEAD #{git_sha(@repo).first(7)} · 1 commit behind running · no local CI", ship_line
  end

  test "after a failed status check, says how old the running version is" do
    @app.status_snapshots.update_all(checked_at: Time.zone.local(2026, 10, 15, 16, 32))
    @app.status_snapshots.create!(error: "ssh: communication with agent failed", checked_at: Time.current)

    assert_equal "HEAD #{@running.first(7)} · same as running (as of Oct 15, 16:32) · no local CI", ship_line
  end

  test "warns when HEAD and the running version have diverged" do
    git(@repo, "reset", "-q", "--hard", "#{@running}~1")
    head = commit(@repo, "Elsewhere")

    assert_equal "HEAD #{head.first(7)} · 1 ahead, 1 behind running · no local CI", ship_line
    assert_includes deploy_confirm, "Warning: HEAD is 1 commit behind the running version"
  end

  test "warns when HEAD is on another branch" do
    git(@repo, "checkout", "-q", "-b", "feature-x")
    head = commit(@repo, "Try something")

    assert_equal "HEAD #{head.first(7)} on feature-x · 1 commit ahead of running · no local CI", ship_line
    assert_includes deploy_confirm, "Warning: HEAD is on branch feature-x, not main or master."
  end

  test "warns when HEAD is detached" do
    git(@repo, "checkout", "-q", "--detach")

    assert_equal "HEAD #{@running.first(7)} detached · same as running · no local CI", ship_line
    assert_includes deploy_confirm, "Warning: HEAD is detached, not on main or master."
  end

  test "says when the running version is unknown" do
    @app.status_snapshots.delete_all

    assert_equal "HEAD #{@running.first(7)} · running version unknown · no local CI", ship_line
  end

  test "says when the repo can't be read" do
    @app.update!(repo_path: "/nonexistent/repo")

    assert_equal "Can't read the repo's HEAD", ship_line
  end

  test "the confirm names the commit and repeats the warnings" do
    git(@repo, "reset", "-q", "--hard", "#{@running}~1")
    File.write(File.join(@repo, "about.html.erb"), "new page")

    confirm = deploy_confirm

    assert_includes confirm, "Kamal will build #{git_sha(@repo).first(7)} from #{@repo}"
    assert_includes confirm, "HEAD is 1 commit behind the running version"
    assert_includes confirm, "Uncommitted changes won't be included"
  end

  def with_local_ci(gh_answer, &block)
    FileUtils.mkdir_p(File.join(@repo, ".githooks"))
    File.write(File.join(@repo, ".githooks/pre-push"), "bin/ci && gh signoff\n")
    @head = commit(@repo, "Add local CI")
    CiSignoff.cache.clear
    @gh_calls = File.join(@repo, ".git", "gh-calls")
    with_fake_command("gh", %(echo x >> #{@gh_calls}; echo #{gh_answer}), &block)
  end

  def gh_call_count
    File.exist?(@gh_calls) ? File.readlines(@gh_calls).size : 0
  end

  test "says when local CI passed" do
    with_local_ci("success") do
      assert_equal "HEAD #{@head.first(7)} · 1 commit ahead of running · CI passed", ship_line
      assert_not_includes deploy_confirm, "CI"
    end
  end

  test "warns when local CI hasn't signed off" do
    with_local_ci("none") do
      assert_equal "HEAD #{@head.first(7)} · 1 commit ahead of running · CI not passed", ship_line
      assert_includes deploy_confirm, "Warning: Local CI hasn't signed off on #{@head.first(7)} (not pushed, or CI not run)."
    end
  end

  test "warns when local CI failed" do
    with_local_ci("failure") do
      assert_equal "HEAD #{@head.first(7)} · 1 commit ahead of running · CI failed", ship_line
      assert_includes deploy_confirm, "Warning: Local CI failed on #{@head.first(7)}."
    end
  end

  test "says when GitHub can't be asked" do
    with_local_ci("x; exit 1") do
      assert_equal "HEAD #{@head.first(7)} · 1 commit ahead of running · CI status unknown", ship_line
      assert_includes deploy_confirm, "Warning: Couldn't check whether local CI passed."
    end
  end

  test "the confirm text is fetched fresh, so a commit made after the page loaded is named" do
    get app_path(@app)
    head = commit(@repo, "Made after the page loaded")

    get app_ship_preview_path(@app, format: :text)

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_includes response.body, "Kamal will build #{head.first(7)} from #{@repo}"
  end

  test "the deploy controls can be re-rendered fresh as a turbo stream" do
    head = commit(@repo, "Made after the page loaded")

    get app_ship_preview_path(@app), as: :turbo_stream

    assert_turbo_stream action: "replace", target: "deploy_controls_app_#{@app.id}" do
      assert_select ".ship-preview", /#{head.first(7)}/
    end
  end

  test "the Deploy button says where to fetch its confirm text" do
    get app_path(@app)

    assert_select "form[action='#{app_deploys_path(@app)}'] [data-confirm-url='#{app_ship_preview_path(@app, format: :text)}']"
  end

  test "the fresh preview requires sign in" do
    delete session_path
    get app_ship_preview_path(@app, format: :text)
    assert_response :redirect
  end

  test "switching back to the tab reuses the last CI answer instead of asking GitHub" do
    with_local_ci("success") do
      get app_ship_preview_path(@app), as: :turbo_stream

      assert_select ".ship-preview", /CI not checked/
      assert_equal 0, gh_call_count
    end
  end

  test "the Deploy confirm asks GitHub fresh" do
    with_local_ci("none") do
      get app_ship_preview_path(@app, format: :text)

      assert_includes response.body, "Local CI hasn't signed off"
      assert_equal 1, gh_call_count
    end
  end

  test "Check CI asks GitHub and redraws the deploy controls" do
    with_local_ci("success") do
      post app_ci_check_path(@app), as: :turbo_stream

      assert_turbo_stream action: "replace", target: "deploy_controls_app_#{@app.id}" do
        assert_select ".ship-preview", /CI passed/
      end
      assert_equal 1, gh_call_count
    end
  end

  test "the Check CI button shows only while CI hasn't passed" do
    with_local_ci("none") do
      get app_path(@app)
      assert_select "form[action='#{app_ci_check_path(@app)}']"
    end

    with_local_ci("success") do
      get app_path(@app)
      assert_select "form[action='#{app_ci_check_path(@app)}']", count: 0
    end
  end
end
