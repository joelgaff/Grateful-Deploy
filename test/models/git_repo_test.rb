require "test_helper"

# The throwaway repos must stay throwaway even when git's own variables are set, as they are for
# a hook run from a worktree (GIT_DIR) or a shell that exports them: otherwise the helper's commits
# land in whatever repository those variables name.
class GitRepoTest < ActiveSupport::TestCase
  test "building and committing ignore GIT_DIR and GIT_WORK_TREE from the environment" do
    decoy = Dir.mktmpdir
    system("git", "-C", decoy, "init", "-q", "-b", "main", exception: true)
    before = `git -C #{decoy} rev-list --all`.lines.size
    saved = ENV.values_at("GIT_DIR", "GIT_WORK_TREE")
    ENV["GIT_DIR"], ENV["GIT_WORK_TREE"] = File.join(decoy, ".git"), decoy

    repo = build_git_repo
    sha = commit(repo, "Second")

    ENV["GIT_DIR"], ENV["GIT_WORK_TREE"] = saved
    assert_equal before, `git -C #{decoy} rev-list --all`.lines.size, "nothing was committed to the repository GIT_DIR names"
    assert_equal sha, `git -C #{repo} rev-parse HEAD`.strip
    assert_equal 2, `git -C #{repo} rev-list --count HEAD`.to_i
  ensure
    ENV["GIT_DIR"], ENV["GIT_WORK_TREE"] = saved if saved
    FileUtils.rm_rf(decoy) if decoy
  end
end
