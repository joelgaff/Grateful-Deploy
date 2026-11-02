require "test_helper"

# The app page follows deploys live: Deploy button, rollback list, history.
class AppPageBroadcastsTest < ActiveSupport::TestCase
  setup { @app = apps(:storefront) }

  def broadcast(name)
    capture_turbo_stream_broadcasts(@app).select { it["target"] == "#{name}_app_#{@app.id}" }.last&.to_html
  end

  test "queuing a deploy disables Deploy and rollbacks and adds it to the history" do
    deploy = @app.start_deploy!

    assert_includes broadcast(:deploy_controls), "Deploy in progress"
    assert_includes broadcast(:rollbacks), "disabled"
    assert_includes broadcast(:deploy_history), app_deploy_path(@app, deploy)
  end

  test "finishing a deploy brings the Deploy button back" do
    deploy = @app.start_deploy!
    deploy.start!

    deploy.finish!(0)

    assert_not_includes broadcast(:deploy_controls), "Deploy in progress"
    assert_includes broadcast(:deploy_controls), "Deploy"
    assert_not_includes broadcast(:rollbacks), "disabled"
  end

  test "background redraws never ask GitHub about CI" do
    repo = build_git_repo
    FileUtils.mkdir_p(File.join(repo, ".githooks"))
    File.write(File.join(repo, ".githooks/pre-push"), "gh signoff\n")
    commit(repo, "Add local CI")
    @app.update!(repo_path: repo)
    CiSignoff.cache.clear
    calls = File.join(repo, ".git", "gh-calls")

    with_fake_command("gh", "echo x >> #{calls}; echo success") { @app.broadcast_page }

    assert_not File.exist?(calls), "asked GitHub"
    assert_includes broadcast(:deploy_controls), "CI not checked"
  end

  private

  def app_deploy_path(*) = Rails.application.routes.url_helpers.app_deploy_path(*)
end
