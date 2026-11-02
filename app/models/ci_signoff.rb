# Whether local CI (bin/ci in .githooks/pre-push, then `gh signoff`) passed for
# a commit, read from the "signoff" commit status on GitHub. GitHub is asked
# only for a fresh read (page load, Deploy click, Check CI button), never by
# background redraws, which reuse the last answer. A pass never changes for a
# commit, so it is never asked again.
class CiSignoff
  STATES = { "success" => :passed, "failure" => :failed, "error" => :failed }.freeze
  # The signoff status's state, or "none" when the commit has no signoff.
  JQ = '[.statuses[] | select(.context == "signoff") | .state] | first // "none"'.freeze
  # Shared by the web server and the job workers (separate processes).
  mattr_accessor :cache, default: Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new :
                                    ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp/cache/ci_signoff"))
  mattr_accessor :timeout, default: 5 # seconds

  def initialize(repo_path, sha)
    @repo_path, @sha = repo_path, sha
  end

  # :passed, :failed, :missing, :unknown, :not_set_up, or :unchecked (a
  # background read before anything has asked GitHub).
  def state(fresh: false)
    return :not_set_up unless set_up?
    return :unknown unless @sha.to_s.match?(GitHead::SHA)

    cached = cache.read(cache_key)
    return cached || :unchecked unless fresh && cached != :passed

    ask_github.tap { cache.write(cache_key, it) }
  end

  private

  def set_up?
    File.read(File.join(@repo_path, ".githooks/pre-push")).include?("signoff")
  rescue SystemCallError
    false
  end

  def ask_github
    output = QuickCommand.capture({}, "gh", "api", "repos/{owner}/{repo}/commits/#{@sha}/status", "--jq", JQ,
                                  chdir: @repo_path, timeout: timeout)
    return :unknown unless output

    # The last line: a gh wrapper may print its own lines first.
    STATES.fetch(output.lines.last.to_s.strip, :missing)
  end

  def cache_key
    [ "ci_signoff", @repo_path, @sha ]
  end
end
