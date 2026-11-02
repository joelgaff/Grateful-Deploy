# The commit a repo's HEAD points at — what `kamal deploy` will build.
# Returns nils when the repo can't be read; the deploy itself will then fail loudly.
module GitHead
  mattr_accessor :timeout, default: 5 # seconds

  # A plain commit sha. Anything else (a version from docker output, say) must
  # not reach git or gh as an argument: one starting with "-" is an option.
  SHA = /\A\h{7,40}\z/

  def self.read(repo_path)
    log = git(repo_path, "log", "-1", "--format=%H%n%s")
    sha, message = log&.lines&.map(&:chomp)
    { git_sha: sha, git_message: message, git_branch: git(repo_path, "rev-parse", "--abbrev-ref", "HEAD")&.chomp }
  end

  # GIT_OPTIONAL_LOCKS=0: read-only, so `git status` never takes .git/index.lock
  # while you're committing in the same repo.
  def self.git(repo_path, *args)
    QuickCommand.capture({ "GIT_OPTIONAL_LOCKS" => "0" }, "git", "-C", repo_path, *args, timeout: timeout)
  end
end
