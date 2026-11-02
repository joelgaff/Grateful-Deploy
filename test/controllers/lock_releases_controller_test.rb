require "test_helper"

class LockReleasesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  DETAILS = "Locked by: Joel at 2026-10-17T18:02:11Z\nVersion: 3f82b485b194\nMessage: Automatic deploy lock".freeze

  setup { sign_in_as users(:owner) }

  def lock_storefront
    servers(:nbg).server_snapshots.create!(checked_at: Time.current, kamal_locks: { "lock-storefront-nbg" => DETAILS })
  end

  test "releases a held lock through the deploy queue and shows its output page" do
    lock_storefront

    assert_enqueued_with(job: DeployJob) { post app_lock_releases_path(apps(:storefront)) }

    deploy = apps(:storefront).deploys.order(:created_at).last
    assert deploy.release_lock_kind?
    assert_redirected_to app_deploy_path(apps(:storefront), deploy)
  end

  test "refuses when no lock is held" do
    assert_no_enqueued_jobs { post app_lock_releases_path(apps(:storefront)) }

    assert_redirected_to app_path(apps(:storefront))
    assert_equal "No Kamal deploy lock is held for storefront", flash[:alert]
  end

  test "the app page shows who holds the lock and a confirmed Release button" do
    lock_storefront

    get app_path(apps(:storefront))

    assert_select ".kamal-lock", /Locked by: Joel at 2026-10-17T18:02:11Z/
    assert_select ".kamal-lock", /Version: 3f82b485b194/
    assert_select "form[action=?] button[data-turbo-confirm*=?]", app_lock_releases_path(apps(:storefront)),
                  "two deploys", text: "Release Kamal lock"
    assert_select "button[disabled]", "Deploy"
  end

  test "no lock, no Release button" do
    get app_path(apps(:storefront))

    assert_select ".kamal-lock", false
    assert_select "form[action=?]", app_lock_releases_path(apps(:storefront)), false
  end

  test "a release's page leaves out the commit and branch, which don't apply" do
    lock_storefront
    deploy = apps(:storefront).start_deploy!(kind: "release_lock")

    get app_deploy_path(apps(:storefront), deploy)

    assert_select "h1", /release lock/i
    assert_select ".deploy-facts dt", text: "Commit", count: 0
    assert_select ".deploy-facts dt", text: "Branch", count: 0
  end
end
