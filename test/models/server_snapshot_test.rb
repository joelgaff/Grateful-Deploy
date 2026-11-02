require "test_helper"

class ServerSnapshotTest < ActiveSupport::TestCase
  test "a server's latest snapshot is its most recent check" do
    assert_equal server_snapshots(:nbg_now), servers(:nbg).latest_server_snapshot
  end

  test "containers come back as a list with their memory" do
    proxy = server_snapshots(:nbg_now).containers.first

    assert_equal "kamal-proxy", proxy["name"]
    assert_equal 7_950_000, proxy["memory_bytes"]
  end

  test "prunes snapshots older than a week" do
    ServerSnapshot.prune

    assert_not ServerSnapshot.exists?(ActiveRecord::FixtureSet.identify(:nbg_old))
    assert ServerSnapshot.exists?(server_snapshots(:nbg_now).id)
  end
end
