require "test_helper"

class ServerRefreshStatusTest < ActiveSupport::TestCase
  setup do
    @server = servers(:nbg)
    @outputs = { docker_ps: file_fixture("docker_ps.jsonl").read, docker_stats: file_fixture("docker_stats.jsonl").read,
                 free: file_fixture("free.txt").read, df: file_fixture("df.txt").read,
                 loadavg: file_fixture("loadavg.txt").read, kamal_locks: file_fixture("kamal_locks.txt").read }
    @probe = ServerProbe.new(@server, runner: ->(command) { @outputs.fetch(command) })
    @health = ->(app) { HealthCheck::Result.new(code: app.name == "storefront" ? 200 : 502, response_ms: 40, error: nil) }
  end

  test "records a snapshot per active app from the probe and health check" do
    freeze_time do
      @server.refresh_status!(probe: @probe, health: @health)

      storefront = apps(:storefront).latest_status_snapshot
      assert_equal Time.current, storefront.checked_at
      assert_equal "f5956902a92a15920788c2d4e319966db0565461", storefront.version
      assert_equal (352.3 * 1024**2).round, storefront.memory_bytes
      assert storefront.healthy?

      incidents = apps(:incidents).latest_status_snapshot
      assert_equal "running", incidents.container_state
      assert_equal 502, incidents.health_code
      assert_not incidents.healthy?
    end
  end

  test "records Kamal's deploy locks on the server snapshot" do
    @server.refresh_status!(probe: @probe, health: @health)

    assert_equal %w[lock-blog lock-storefront-nbg], @server.latest_server_snapshot.kamal_locks.keys.sort
    assert_match(/Locked by: Joel/, @server.latest_server_snapshot.kamal_locks["lock-storefront-nbg"])
  end

  test "an app with no running container is recorded as missing" do
    @outputs[:docker_ps] = ""

    @server.refresh_status!(probe: @probe, health: @health)

    assert_equal "missing", apps(:storefront).latest_status_snapshot.container_state
  end

  def storefront_container(sha, state:, status:)
    { "Image" => "localhost:5555/storefront:#{sha}", "Labels" => "destination=nbg,role=web,service=storefront",
      "Names" => "storefront-web-nbg-#{sha}", "State" => state, "Status" => status }.to_json
  end

  test "a stopped app is recorded as stopped with its version, and isn't health-checked" do
    stopped = "a7227ad0c1e2b3f4a5b6c7d8e9f0a1b2c3d4e5f6"
    @outputs[:docker_ps] = @outputs[:docker_ps].lines.grep_v(/service=storefront/).join +
      storefront_container(stopped, state: "exited", status: "Exited (0) 5 minutes ago") + "\n" +
      storefront_container("f5956902a92a15920788c2d4e319966db0565461", state: "exited", status: "Exited (0) 2 days ago") + "\n"
    checked = []

    @server.refresh_status!(probe: @probe, health: ->(app) { checked << app.name; @health.(app) })

    snapshot = apps(:storefront).latest_status_snapshot
    assert snapshot.stopped?
    assert_equal stopped, snapshot.version
    assert_nil snapshot.health_code
    assert_nil snapshot.error
    assert_equal stopped, apps(:storefront).stopped_version
    assert_not_includes checked, "storefront"
    assert_includes checked, "incidents"
    assert_not(@server.latest_server_snapshot.containers.any? { it["service"] == "storefront" }, "stopped containers stay off the servers page")
  end

  test "the running container wins over older stopped versions Kamal keeps for rollback" do
    @outputs[:docker_ps] += storefront_container("0123456789abcdef0123456789abcdef01234567", state: "exited", status: "Exited (0) 9 days ago") + "\n"

    @server.refresh_status!(probe: @probe, health: @health)

    snapshot = apps(:storefront).latest_status_snapshot
    assert_equal "running", snapshot.container_state
    assert_equal "f5956902a92a15920788c2d4e319966db0565461", snapshot.version
    assert_nil apps(:storefront).stopped_version
  end

  test "an ssh failure is recorded on every app instead of raising" do
    failing = ServerProbe.new(@server, runner: ->(_) { raise ServerProbe::Error, "Unlock 1Password" })

    @server.refresh_status!(probe: failing, health: @health)

    snapshot = apps(:storefront).latest_status_snapshot
    assert_nil snapshot.container_state
    assert_equal "Unlock 1Password", snapshot.error
    assert_equal 200, snapshot.health_code
  end

  test "inactive apps are skipped" do
    apps(:incidents).update!(active: false)

    assert_difference -> { StatusSnapshot.count }, 1 do
      @server.refresh_status!(probe: @probe, health: @health)
    end
  end

  test "replaces each app's card on the apps page" do
    @server.refresh_status!(probe: @probe, health: @health)

    streams = capture_turbo_stream_broadcasts("apps")
    assert_equal [ "card_app_#{apps(:incidents).id}", "card_app_#{apps(:storefront).id}" ].sort, streams.map { it["target"] }.sort
    assert(streams.all? { it["action"] == "replace" })
  end

  test "updates each app's page: health and running version, what would ship, rollbacks" do
    app = apps(:storefront)

    @server.refresh_status!(probe: @probe, health: @health)

    targets = capture_turbo_stream_broadcasts(app).map { it["target"] }
    %i[header deploy_controls facts rollbacks].each { assert_includes targets, "#{it}_app_#{app.id}" }
    facts = capture_turbo_stream_broadcasts(app).find { it["target"] == "facts_app_#{app.id}" }
    assert_includes facts.to_html, app.reload.running_status_snapshot.short_version
  end

  test "a failed page redraw doesn't skip the other apps' status" do
    assert_difference -> { StatusSnapshot.count }, @server.apps.where(active: true).count do
      with_failing_broadcasts { @server.refresh_status!(probe: @probe, health: @health) }
    end
  end

  test "records the server's memory, disk and containers" do
    @server.refresh_status!(probe: @probe, health: @health)

    snapshot = @server.latest_server_snapshot
    assert_equal 8_122_322_944, snapshot.memory_total
    assert_equal 434_176, snapshot.swap_used
    assert_equal 11_338_067_968, snapshot.disk_used
    assert_equal 0.21, snapshot.load_1
    assert_equal 0.14, snapshot.load_5
    assert_equal 0.10, snapshot.load_15
    assert_equal 4, snapshot.cpus
    assert_equal 6, snapshot.containers.size
    storefront = snapshot.containers.find { it["service"] == "storefront" }
    assert_equal "f5956902a92a15920788c2d4e319966db0565461", storefront["version"]
    assert_equal (352.3 * 1024**2).round, storefront["memory_bytes"]
    assert_nil snapshot.error
  end

  test "an ssh failure is recorded on the server snapshot too" do
    failing = ServerProbe.new(@server, runner: ->(_) { raise ServerProbe::Error, "Unlock 1Password" })

    @server.refresh_status!(probe: failing, health: @health)

    snapshot = @server.latest_server_snapshot
    assert_equal "Unlock 1Password", snapshot.error
    assert_nil snapshot.memory_total
    assert_equal [], snapshot.containers
    assert_nil snapshot.kamal_locks # unknown, not "no locks"
  end

  test "replaces the server's panel on the servers page" do
    @server.refresh_status!(probe: @probe, health: @health)

    streams = capture_turbo_stream_broadcasts("servers")
    assert_equal [ "panel_server_#{@server.id}" ], streams.map { it["target"] }
    assert_includes streams.first.to_html, "kamal-proxy"
  end
end
