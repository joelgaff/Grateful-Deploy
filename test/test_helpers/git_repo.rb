# Real throwaway git repos (in a fake Kamal repo), for code that reads HEAD and status.
module GitRepo
  # Variables git sets for hooks (and a shell may export) that point every git command at one
  # repository, whatever -C says. Cleared for the helper's own commands; test_helper.rb also drops
  # them at load, for the app code the tests run.
  GIT_LOCATION_VARIABLES = %w[GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE].freeze
  CLEAN_GIT_ENV = GIT_LOCATION_VARIABLES.to_h { |name| [ name, nil ] }.freeze

  def build_git_repo
    build_fake_kamal_repo("exit 0").tap do |repo|
      git(repo, "init", "-b", "main")
      git(repo, "add", ".")
      commit(repo, "First commit")
    end
  end

  # Commits everything (or nothing) and returns the new sha.
  def commit(repo, message)
    git(repo, "add", ".")
    git(repo, "-c", "user.email=t@example.com", "-c", "user.name=T", "commit", "--allow-empty", "-m", message)
    git_sha(repo)
  end

  def git_sha(repo, ref = "HEAD")
    IO.popen(CLEAN_GIT_ENV, [ "git", "-C", repo, "rev-parse", ref ], &:read).strip
  end

  def git(repo, *args)
    system(CLEAN_GIT_ENV, "git", "-C", repo, *args, exception: true, out: File::NULL, err: File::NULL)
  end
end
