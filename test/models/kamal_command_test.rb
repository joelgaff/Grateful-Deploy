require "test_helper"

class KamalCommandTest < ActiveSupport::TestCase
  setup do
    @repo = build_fake_kamal_repo(<<~SH)
      echo "args: $*"
      echo "dir: $(pwd)"
      echo "RAILS_MASTER_KEY=#{"ab" * 16}" >&2
      [ "$1" = "deploy" ] && exit 0 || exit 3
    SH
    @app = apps(:storefront)
    @app.repo_path = @repo
  end

  test "builds argument arrays from the allowlist and the app's target" do
    assert_equal %w[bin/kamal deploy -d nbg], KamalCommand.new(@app, :deploy).argv
    assert_equal %w[bin/kamal lock release -d nbg], KamalCommand.new(@app, :release_lock).argv
    assert_equal %w[bin/kamal app logs -n 200 --skip-hooks -d nbg], KamalCommand.new(@app, :logs, lines: 200).argv

    incidents = apps(:incidents)
    incidents.kamal_binary = "global"
    sha = "7d1e0f2a9c"
    resolver = GlobalKamal.resolver
    GlobalKamal.reset
    GlobalKamal.resolver = ->(_dir) { "/opt/ruby/bin/kamal\n" }
    assert_equal [ "/opt/ruby/bin/kamal", "rollback", sha, "-c", "config/deploy.nbg.yml" ],
                 KamalCommand.new(incidents, :rollback, version: sha).argv
  ensure
    GlobalKamal.resolver = resolver
    GlobalKamal.reset
  end

  test "read-only log commands skip Kamal hooks, so they never run a repo's hook scripts; deploys keep them" do
    assert_equal %w[bin/kamal app logs -n 200 --skip-hooks -d nbg], KamalCommand.new(@app, :logs, lines: 200).argv
    assert_equal %w[bin/kamal app logs -f --skip-hooks -d nbg], KamalCommand.new(@app, :logs_follow).argv
    assert_not_includes KamalCommand.new(@app, :deploy).argv, "--skip-hooks"
    assert_not_includes KamalCommand.new(@app, :rollback, version: "7d1e0f2a9c").argv, "--skip-hooks"
  end

  test "refuses actions that are not on the allowlist" do
    assert_raises(KamalCommand::NotAllowed) { KamalCommand.new(@app, :remove) }
    assert_raises(KamalCommand::NotAllowed) { KamalCommand.new(@app, "app exec") }
  end

  test "the allowlist holds only the commands Grateful Deploy uses" do
    assert_equal %i[deploy rollback release_lock stop start logs logs_follow], KamalCommand::ACTIONS.keys
    assert_raises(KamalCommand::NotAllowed) { KamalCommand.new(@app, :version) }
    assert_raises(KamalCommand::NotAllowed) { KamalCommand.new(@app, :details) }
  end

  test "stops the app, and starts a stopped one by its version rather than the repo's HEAD" do
    assert_equal %w[bin/kamal app stop -d nbg], KamalCommand.new(@app, :stop).argv
    assert_equal %w[bin/kamal app start --version 7d1e0f2a9c -d nbg], KamalCommand.new(@app, :start, version: "7d1e0f2a9c").argv
  end

  test "rejects start versions that are not git shas" do
    [ nil, "", "latest; rm -rf /", "--help" ].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { KamalCommand.new(@app, :start, version: bad) }
    end
  end

  test "rejects rollback versions that are not git shas" do
    [ nil, "", "abc", "latest; rm -rf /", "--help", "g" * 10 ].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { KamalCommand.new(@app, :rollback, version: bad) }
    end
  end

  test "rejects log line counts outside 1..1000" do
    [ 0, 1001, "200; ls", nil ].each do |bad|
      assert_raises(ArgumentError, bad.inspect) { KamalCommand.new(@app, :logs, lines: bad) }
    end
  end

  test "runs inside the repo, yields scrubbed stdout and stderr lines, returns the exit status" do
    lines = []
    status = KamalCommand.new(@app, :deploy).run { |line| lines << line }

    assert status.success?
    assert_includes lines, "args: deploy -d nbg"
    assert_includes lines, "dir: #{File.realpath(@repo)}"
    assert_includes lines, "RAILS_MASTER_KEY=[FILTERED]"
    assert lines.none? { |l| l.include?("ab" * 16) }
  end

  test "runs Kamal with the app's kamal_env, leaving a value not set yet unset" do
    @app.repo_path = build_fake_kamal_repo(%(echo "server=${SHOP_SERVER-unset} domain=${SHOP_DOMAIN-unset}"))
    @app.kamal_env = { "SHOP_SERVER" => "198.51.100.7", "SHOP_DOMAIN" => nil }
    lines = []

    KamalCommand.new(@app, :deploy).run { |line| lines << line }

    assert_includes lines, "server=198.51.100.7 domain=unset"
  end

  test "reports a failing exit status" do
    status = KamalCommand.new(@app, :logs, lines: 10).run { }

    assert_equal 3, status.exitstatus
  end

  test "reports the pid of a process group that can be stopped as a whole" do
    @app.repo_path = build_fake_kamal_repo("echo started\nsleep 30 & wait")
    lines = []
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    status = KamalCommand.new(@app, :logs_follow).run(on_start: ->(pid) {
      Thread.new { sleep 0.5; Process.kill("TERM", -Process.getpgid(pid)) }
    }) { |line| lines << line }

    assert_equal [ "started" ], lines
    assert_not status.success?
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
  end
end
