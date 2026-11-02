require "test_helper"

class GitHeadTest < ActiveSupport::TestCase
  setup { @repo = build_git_repo }

  test "git never rewrites the repo's index, so it can't hold the lock your own git needs" do
    index = File.join(@repo, ".git/index")
    FileUtils.touch(File.join(@repo, "bin/kamal"), mtime: Time.now + 5) # same content, new stat: status wants to refresh
    before = File.stat(index).then { [ it.ino, it.mtime ] }

    GitHead.git(@repo, "status", "--porcelain")

    assert_equal before, File.stat(index).then { [ it.ino, it.mtime ] }
  end

  test "a git that hangs is stopped, and reads as unreadable" do
    timeout, GitHead.timeout = GitHead.timeout, 0.5
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    with_fake_command("git", "sleep 30") { assert_nil GitHead.git(@repo, "status", "--porcelain") }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  ensure
    GitHead.timeout = timeout
  end
end
