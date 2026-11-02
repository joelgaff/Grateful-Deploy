require "open3"

# Runs one allowlisted Kamal command for an app, inside its repo, and yields
# scrubbed output lines. Arguments are always an array — never a shell string —
# and nothing here comes from request params except the action name.
class KamalCommand
  class NotAllowed < StandardError; end

  ACTIONS = {
    deploy: ->(**) { %w[deploy] },
    rollback: ->(version:, **) { [ "rollback", version ] },
    # Clears a lock left by a deploy Grateful Deploy didn't start (or one that crashed).
    release_lock: ->(**) { %w[lock release] },
    stop: ->(**) { %w[app stop] },
    # By version: Kamal otherwise looks for the container of the repo's HEAD,
    # which isn't the stopped one once HEAD has moved.
    start: ->(version:, **) { [ "app", "start", "--version", version ] },
    # Read-only, so no hooks: Kamal would otherwise run the repo's pre-connect
    # hook (with its secrets loaded) before connecting.
    logs: ->(lines:, **) { [ "app", "logs", "-n", lines.to_s, "--skip-hooks" ] },
    logs_follow: ->(**) { %w[app logs -f --skip-hooks] }
  }.freeze

  LOG_LINES = 1..1000
  # mise picks the Ruby each repo pins, the same as running Kamal in a terminal there.
  LAUNCHER = %w[mise exec --].freeze

  attr_reader :app, :action

  def initialize(app, action, version: nil, lines: nil)
    @app = app
    @action = action.to_s.to_sym
    raise NotAllowed, "#{action.inspect} is not allowed" unless ACTIONS.key?(@action)

    @version = validate_version(version) if @action.in?(%i[rollback start])
    @lines = validate_lines(lines) if @action == :logs
  end

  # What runs, as one line to show: the app's kamal_env, then the command.
  def display
    env = app.kamal_env.map { |name, value| "#{name}=#{value.presence || "(not set)"}" }
    [ *env, *argv ].join(" ")
  end

  def argv
    [ app.kamal_executable, *ACTIONS.fetch(action).call(version: @version, lines: @lines), *app.kamal_target_args ]
  end

  # Runs in its own process group, so a stop can end Kamal and the ssh it spawns.
  # on_start receives the group leader's pid. The app's kamal_env is set for
  # Kamal only; a value not set yet (nil) is unset, never inherited.
  def run(on_start: nil)
    Bundler.with_unbundled_env do
      Open3.popen2e(app.kamal_env, *LAUNCHER, *argv, chdir: app.repo_path, pgroup: true) do |stdin, output, wait|
        stdin.close
        on_start&.call(wait.pid)
        output.each_line { |line| yield SecretScrubber.scrub(line.scrub.chomp) }
        wait.value
      end
    end
  end

  private

  def validate_version(version)
    version.to_s.match?(GitHead::SHA) ? version : raise(ArgumentError, "#{@action} version must be a git sha")
  end

  def validate_lines(lines)
    count = Integer(lines.to_s, 10, exception: false)
    LOG_LINES.cover?(count) ? count : raise(ArgumentError, "log lines must be within #{LOG_LINES}")
  end
end
