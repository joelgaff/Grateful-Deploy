require "test_helper"

class ServerProbeTest < ActiveSupport::TestCase
  setup do
    @outputs = {
      docker_ps: file_fixture("docker_ps.jsonl").read,
      docker_stats: file_fixture("docker_stats.jsonl").read,
      free: file_fixture("free.txt").read,
      df: file_fixture("df.txt").read
    }
    @probe = ServerProbe.new(servers(:nbg), runner: ->(command) { @outputs.fetch(command) })
  end

  test "reads each container's Kamal version, state and memory" do
    storefront = @probe.containers.find { |c| c.name == "storefront-web-nbg-f5956902a92a15920788c2d4e319966db0565461" }

    assert_equal "f5956902a92a15920788c2d4e319966db0565461", storefront.version
    assert_equal "storefront", storefront.service
    assert_equal "running", storefront.state
    assert_equal "Up 5 days", storefront.status
    assert_equal (352.3 * 1024**2).round, storefront.memory_bytes
  end

  # docker ps joins labels with commas, and a Compose label's value can hold
  # commas of its own (Immich's depends_on, on the laptop).
  test "a label value with commas in it doesn't break the others" do
    @outputs[:docker_ps] = { Names: "immich_server", Image: "immich", State: "running", Status: "Up 2 days",
                             Labels: "com.docker.compose.depends_on=database:service_started:false,redis:service_started:false,service=immich,role=web" }.to_json
    immich = @probe.containers.sole

    assert_equal [ "immich", "web" ], [ immich.service, immich.role ]
  end

  test "only Kamal web roles count as an app's web container" do
    web = @probe.containers.select(&:web?).map(&:service)

    assert_includes web, "blog"
    assert_not_includes web, "blog-litestream"
    assert_not_includes web, "kamal-proxy"
  end

  test "runs only these read-only commands on the server" do
    assert_equal({
      docker_ps: "docker ps -a --format '{{json .}}'",
      docker_stats: "docker stats --no-stream --format '{{json .}}'",
      free: "free -b",
      df: "df -B1 /",
      loadavg: "cat /proc/loadavg && nproc",
      kamal_locks: %(for d in .kamal/lock-*; do [ -d "$d" ] && echo "== ${d##*/}" && base64 -d "$d/details" && echo; done; true)
    }, ServerProbe::COMMANDS)
  end

  test "reads Kamal's deploy locks: lock folder name and the details Kamal wrote" do
    probe = ServerProbe.new(servers(:nbg), runner: ->(_) { file_fixture("kamal_locks.txt").read })

    assert_equal({ "lock-storefront-nbg" => "Locked by: Joel at 2026-10-17T18:02:11Z\nVersion: 3f82b485b194\nMessage: Automatic deploy lock",
                   "lock-blog" => "Locked by: Joel at 2026-10-17T18:05:40Z\nVersion: 8d2f3f68a5c7\nMessage: Manual lock" },
                 probe.kamal_locks)
  end

  test "lock details are masked like any other output" do
    output = "== lock-storefront-nbg\nLocked by: joel@example.test at 2026-10-17T18:02:11Z\nMessage: token=abc123secret\n"
    probe = ServerProbe.new(servers(:nbg), runner: ->(_) { output })

    assert_equal "Locked by: [FILTERED] at 2026-10-17T18:02:11Z\nMessage: token=[FILTERED]", probe.kamal_locks["lock-storefront-nbg"]
  end

  test "no locks is an empty list" do
    assert_equal({}, ServerProbe.new(servers(:nbg), runner: ->(_) { "" }).kamal_locks)
  end

  test "lists every container with its memory" do
    proxy = @probe.containers.find { |c| c.name == "kamal-proxy" }

    assert_equal "basecamp/kamal-proxy:v0.9.2", proxy.image
    assert_equal (7.582 * 1024**2).round, proxy.memory_bytes
    assert_equal 6, @probe.containers.size
  end
end

class ServerProbeResourcesTest < ActiveSupport::TestCase
  setup do
    outputs = { free: file_fixture("free.txt").read, df: file_fixture("df.txt").read,
                loadavg: file_fixture("loadavg.txt").read }
    @probe = ServerProbe.new(servers(:nbg), runner: ->(command) { outputs.fetch(command) })
  end

  test "reads memory and swap from free -b" do
    memory = @probe.memory

    assert_equal 8_122_322_944, memory.total
    assert_equal 3_722_952_704, memory.used
    assert_equal 4_399_370_240, memory.available
    assert_equal 2_147_479_552, memory.swap_total
    assert_equal 434_176, memory.swap_used
  end

  test "reads the root filesystem from df -B1 /" do
    disk = @probe.disk

    assert_equal 80_279_486_464, disk.total
    assert_equal 11_338_067_968, disk.used
    assert_equal 65_643_118_592, disk.available
  end
end

class ServerProbeLoadTest < ActiveSupport::TestCase
  test "reads 1, 5 and 15 minute load and the cpu count" do
    probe = ServerProbe.new(servers(:nbg), runner: ->(_) { file_fixture("loadavg.txt").read })
    load = probe.load

    assert_equal [ 0.21, 0.14, 0.10 ], [ load.one, load.five, load.fifteen ]
    assert_equal 4, load.cpus
  end
end

class ServerProbe::SshRunnerTest < ActiveSupport::TestCase
  setup do
    @calls = []
    @executor = lambda do |*argv|
      @calls << argv
      output = ServerProbe::COMMANDS.keys.map { |key| "#{ServerProbe::SshRunner.marker(key)}\n#{key} output\n" }.join
      [ output, "", Struct.new(:success?).new(true) ]
    end
    @runner = ServerProbe::SshRunner.new(servers(:nbg), executor: @executor)
  end

  test "runs every read-only command in one ssh connection, because ufw limits port 22" do
    ServerProbe::COMMANDS.each_key { |key| assert_equal "#{key} output\n", @runner.call(key) }

    assert_equal 1, @calls.size
    argv = @calls.first
    assert_equal [ "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "root@203.0.113.10" ], argv.first(6)
    remote = argv.last
    ServerProbe::COMMANDS.each_value { |command| assert_includes remote, command }
  end

  test "the remote script is only fixed commands and markers" do
    expected = ServerProbe::COMMANDS.map { |key, command| "echo '#{ServerProbe::SshRunner.marker(key)}'; #{command}" }.join("; ")

    assert_equal expected, @runner.argv.last
  end

  test "refuses unknown commands" do
    assert_raises(KeyError) { @runner.call(:"rm -rf /") }
  end

  test "explains a locked 1Password agent" do
    error = assert_raises(ServerProbe::Error) do
      ServerProbe::SshRunner.raise_for("sign_and_send_pubkey: communication with agent failed")
    end
    assert_match "Unlock 1Password", error.message
  end

  test "explains a refused connection as the ssh rate limit" do
    error = assert_raises(ServerProbe::Error) do
      ServerProbe::SshRunner.raise_for("ssh: connect to host 203.0.113.10 port 22: Connection refused")
    end
    assert_match "rate limit", error.message
  end
end
