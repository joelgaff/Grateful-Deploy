require "test_helper"

class AppRollbackVersionsTest < ActiveSupport::TestCase
  setup { @app = apps(:storefront) }

  test "offers versions the app has run, newest first, minus the one running now" do
    # storefront_now (f595690…) is running; storefront_old (0041612…) ran before;
    # storefront_done deployed 7d1e0f2… two days ago.
    assert_equal %w[7d1e0f2a9c4b5e6f708192a3b4c5d6e7f8091a2b 0041612645e211e57d08ed7bac117b27a96ac7e9],
                 @app.rollback_versions
  end

  test "skips failed deploys and versions that were never healthy" do
    @app.deploys.create!(kind: "deploy", status: "failed", git_sha: "b" * 40)
    @app.status_snapshots.create!(version: "c" * 40, container_state: "running", health_code: 500, checked_at: 1.hour.ago)

    assert_not_includes @app.rollback_versions, "b" * 40
    assert_not_includes @app.rollback_versions, "c" * 40
  end

  test "a failed status check doesn't put the running version on the list" do
    @app.status_snapshots.create!(error: "ssh: communication with agent failed", checked_at: Time.current)

    assert_not_includes @app.rollback_versions, status_snapshots(:storefront_now).version
  end

  test "keeps at most five" do
    6.times { |i| @app.deploys.create!(kind: "deploy", status: "succeeded", git_sha: i.to_s * 40, created_at: i.hours.ago) }

    assert_equal 5, @app.rollback_versions.size
  end
end
