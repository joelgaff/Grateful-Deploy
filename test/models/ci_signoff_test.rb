require "test_helper"

class CiSignoffTest < ActiveSupport::TestCase
  setup do
    @repo = build_git_repo
    FileUtils.mkdir_p(File.join(@repo, ".githooks"))
    File.write(File.join(@repo, ".githooks/pre-push"), "bin/ci && gh signoff\n")
    @sha = commit(@repo, "Add local CI")
    @calls = File.join(@repo, "gh-calls")
    CiSignoff.cache.clear
  end

  def state_with_gh(output, sha: @sha)
    with_fake_command("gh", %(echo "$@" >> #{@calls}; echo #{output})) { CiSignoff.new(@repo, sha).state(fresh: true) }
  end

  def gh_calls
    File.exist?(@calls) ? File.readlines(@calls) : []
  end

  test "passed when local CI signed off on the commit" do
    assert_equal :passed, state_with_gh("success")
    assert_includes gh_calls.first, "commits/#{@sha}/status"
  end

  test "ignores what a gh wrapper prints first (mise use -g gh writes to stdout)" do
    assert_equal :passed, state_with_gh(%(mise ~/.config/mise/config.toml tools: gh@2.101.0; echo success))
  end

  test "failed when the signoff says so" do
    assert_equal :failed, state_with_gh("failure")
    CiSignoff.cache.clear
    assert_equal :failed, state_with_gh("error")
  end

  test "missing when the commit was never signed off (not pushed, or CI not run)" do
    assert_equal :missing, state_with_gh("none")
    CiSignoff.cache.clear
    assert_equal :missing, state_with_gh("pending")
  end

  test "unknown when gh fails (offline, logged out)" do
    with_fake_command("gh", "exit 1") { assert_equal :unknown, CiSignoff.new(@repo, @sha).state(fresh: true) }
  end

  test "not set up when the repo has no signoff hook, without asking GitHub" do
    FileUtils.rm_rf(File.join(@repo, ".githooks"))

    assert_equal :not_set_up, state_with_gh("success")
    assert_empty gh_calls
  end

  test "unknown for anything but a git sha, without asking GitHub" do
    assert_equal :unknown, state_with_gh("success", sha: "--paginate")
    assert_empty gh_calls
  end

  def background_state(sha: @sha)
    with_fake_command("gh", %(echo "$@" >> #{@calls}; echo success)) { CiSignoff.new(@repo, sha).state }
  end

  test "a background read never asks GitHub, and says unchecked until something has" do
    assert_equal :unchecked, background_state
    assert_empty gh_calls
  end

  test "a background read reuses the last answer, however old" do
    state_with_gh("none")

    travel 1.day do
      assert_equal :missing, background_state
    end
    assert_equal 1, gh_calls.size
  end

  test "a fresh read asks again, unless the commit already passed" do
    state_with_gh("none")
    assert_equal :passed, state_with_gh("success")
    assert_equal :passed, state_with_gh("success")

    assert_equal 2, gh_calls.size
  end
end
