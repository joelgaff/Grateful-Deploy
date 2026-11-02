require "test_helper"

# Kamal's own deploy lock (held by a deploy from a terminal or CI, or left
# behind by one that crashed), as the latest status check saw it.
class AppKamalLockTest < ActiveJob::TestCase
  DETAILS = "Locked by: Joel at 2026-10-17T18:02:11Z\nVersion: 3f82b485b194\nMessage: Automatic deploy lock".freeze

  def locks(names)
    servers(:nbg).server_snapshots.create!(checked_at: Time.current, kamal_locks: names.index_with { DETAILS })
  end

  test "an app finds its own lock by Kamal's folder name: service, plus destination when it has one" do
    locks %w[lock-storefront-nbg lock-incidents]

    assert_equal DETAILS, apps(:storefront).kamal_lock
    assert_equal DETAILS, apps(:incidents).kamal_lock
  end

  test "another app's lock, no locks, or an unreadable check mean no lock for this app" do
    locks %w[lock-storefront-other lock-storefront]
    assert_nil apps(:storefront).kamal_lock

    servers(:nbg).server_snapshots.create!(checked_at: 1.second.from_now, kamal_locks: nil)
    assert_nil apps(:storefront).kamal_lock
  end

  test "a held lock keeps Deploy and Rollback off, saying who holds it" do
    locks %w[lock-storefront-nbg]

    assert_equal "Kamal's deploy lock for storefront is held (Locked by: Joel at 2026-10-17T18:02:11Z). " \
                 "Wait for that deploy to finish, or release the lock", apps(:storefront).deploy_blocked_reason
    assert_no_enqueued_jobs do
      assert_raises(ActiveRecord::RecordInvalid) { apps(:storefront).start_deploy!(kind: "rollback", version: "7d1e0f2") }
    end
  end

  test "the lock can be released only while it's held, through the usual one-at-a-time deploy queue" do
    locks %w[lock-storefront-nbg]

    deploy = nil
    assert_enqueued_with(job: DeployJob) { deploy = apps(:storefront).start_deploy!(kind: "release_lock") }

    assert deploy.release_lock_kind?
    assert_nil deploy.git_sha
  end

  test "releasing is refused when no lock is held, or a kamal_env value isn't set" do
    error = assert_raises(ActiveRecord::RecordInvalid) { apps(:storefront).start_deploy!(kind: "release_lock") }
    assert_includes error.record.errors[:base], "No Kamal deploy lock is held for storefront"

    locks %w[lock-storefront-nbg]
    apps(:storefront).update!(kamal_env: { "STOREFRONT_DOMAIN" => nil })
    error = assert_raises(ActiveRecord::RecordInvalid) { apps(:storefront).start_deploy!(kind: "release_lock") }
    assert_includes error.record.errors[:base], "Set STOREFRONT_DOMAIN in config/fleet.yml before deploying storefront"
  end

  test "a lock release isn't the app's last deploy" do
    locks %w[lock-storefront-nbg]
    deployed = apps(:storefront).deploys.order(:created_at).last
    apps(:storefront).start_deploy!(kind: "release_lock")

    assert_equal deployed, App.find(apps(:storefront).id).latest_deploy
  end
end
