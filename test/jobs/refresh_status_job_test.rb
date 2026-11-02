require "test_helper"

class RefreshStatusJobTest < ActiveJob::TestCase
  setup do
    @refreshed = []
    @refresher = RefreshStatusJob.refresher
    RefreshStatusJob.refresher = ->(server) { @refreshed << server.name }
    @server = servers(:nbg)
  end

  teardown { RefreshStatusJob.refresher = @refresher }

  def checked(ago)
    @server.server_snapshots.delete_all
    @server.server_snapshots.create!(checked_at: ago.ago, error: "SSH connection refused")
  end

  test "checks a server not checked in the last minute" do
    checked(2.minutes)

    RefreshStatusJob.perform_now

    assert_equal [ "nbg" ], @refreshed
  end

  test "skips a server checked less than a minute ago, even if that check failed, so a catch-up burst after sleep is one SSH connection" do
    checked(20.seconds)

    5.times { RefreshStatusJob.perform_now }

    assert_empty @refreshed
  end

  test "Refresh now forces a check" do
    checked(5.seconds)

    RefreshStatusJob.perform_now(force: true)

    assert_equal [ "nbg" ], @refreshed
  end
end
