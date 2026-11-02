require "test_helper"

class StatusSnapshotTest < ActiveSupport::TestCase
  test "an app's latest snapshot is its most recent check" do
    assert_equal status_snapshots(:storefront_now), apps(:storefront).latest_status_snapshot
  end

  test "healthy means a running container and a 2xx health check" do
    assert status_snapshots(:storefront_now).healthy?
    assert_not status_snapshots(:incidents_down).healthy?
    assert_not StatusSnapshot.new(container_state: "running", health_code: nil).healthy?
  end

  test "short version is the first 7 characters of the sha" do
    assert_equal "f595690", status_snapshots(:storefront_now).short_version
    assert_nil status_snapshots(:incidents_down).short_version
  end

  test "prunes snapshots older than a week" do
    StatusSnapshot.prune

    assert_not StatusSnapshot.exists?(ActiveRecord::FixtureSet.identify(:storefront_old))
    assert StatusSnapshot.exists?(status_snapshots(:storefront_now).id)
  end
end
