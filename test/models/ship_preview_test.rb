require "test_helper"

class ShipPreviewTest < ActiveSupport::TestCase
  setup do
    @repo = build_git_repo
    @running = commit(@repo, "Running now")
    @app = apps(:storefront)
    @app.update!(repo_path: @repo)
    @app.status_snapshots.create!(version: @running, container_state: "running", checked_at: Time.current)
  end

  test "names the commit Kamal will build" do
    assert_equal git_sha(@repo).first(7), ShipPreview.new(@app).head_short_sha
  end

  test "knows the branch, and whether it is the main one" do
    assert_equal "main", ShipPreview.new(@app).branch
    assert ShipPreview.new(@app).main_branch?

    git(@repo, "checkout", "-q", "-b", "feature-x")

    assert_equal "feature-x", ShipPreview.new(@app).branch
    assert_not ShipPreview.new(@app).main_branch?
  end

  test "master counts as a main branch; a detached HEAD doesn't" do
    git(@repo, "branch", "-m", "master")
    assert ShipPreview.new(@app).main_branch?

    git(@repo, "checkout", "-q", "--detach")
    assert_nil ShipPreview.new(@app).branch
    assert_not ShipPreview.new(@app).main_branch?
  end

  test "counts commits ahead of the running version" do
    commit(@repo, "Two")
    commit(@repo, "Three")

    preview = ShipPreview.new(@app)

    assert_equal 2, preview.ahead
    assert_equal 0, preview.behind
  end

  test "counts commits the running version has that HEAD doesn't" do
    git(@repo, "reset", "-q", "--hard", "#{@running}~1")

    preview = ShipPreview.new(@app)

    assert_equal 0, preview.ahead
    assert_equal 1, preview.behind
  end

  test "a failed status check doesn't lose the running version" do
    commit(@repo, "Two")
    @app.status_snapshots.create!(error: "ssh: communication with agent failed", checked_at: Time.current)

    preview = ShipPreview.new(@app)

    assert_equal @running, preview.running_version
    assert_equal 1, preview.ahead
  end

  test "no counts when the running version isn't in this repo" do
    @app.status_snapshots.create!(version: "0" * 40, container_state: "running", checked_at: Time.current)

    assert_nil ShipPreview.new(@app).ahead
  end

  test "a running version that isn't a git sha never reaches git" do
    dir = Dir.mktmpdir
    @app.status_snapshots.create!(version: "--output=#{dir}/x", container_state: "running", checked_at: Time.current)

    assert_nil ShipPreview.new(@app).ahead
    assert_empty Dir.children(dir), "git wrote a file named by the running version"
  ensure
    FileUtils.rm_rf(dir)
  end

  test "spots uncommitted changes, including new files" do
    assert_not ShipPreview.new(@app).uncommitted_changes?

    File.write(File.join(@repo, "about.html.erb"), "new page")

    assert ShipPreview.new(@app).uncommitted_changes?
  end

  test "ignores Kamal's own files, which Kamal reads from the working folder" do
    FileUtils.mkdir_p(File.join(@repo, "config"))
    FileUtils.mkdir_p(File.join(@repo, ".kamal"))
    File.write(File.join(@repo, "config/deploy.nbg.yml"), "service: x")
    File.write(File.join(@repo, ".kamal/secrets.nbg"), "KEY=$KEY")

    assert_not ShipPreview.new(@app).uncommitted_changes?
  end

  test "an unreadable repo gives nothing rather than raising" do
    @app.update!(repo_path: "/nonexistent/repo")

    preview = ShipPreview.new(@app)

    assert_nil preview.head_short_sha
    assert_nil preview.ahead
    assert_not preview.uncommitted_changes?
  end
end
