require "test_helper"

class AppsControllerTest < ActionDispatch::IntegrationTest
  test "requires sign in" do
    get root_path

    assert_redirected_to new_session_path
  end

  test "pages carry the Grateful Deploy name in the title and the top bar" do
    sign_in_as users(:owner)

    get root_path

    assert_select "title", "Apps · Grateful Deploy"
    assert_select "meta[name=application-name][content=?]", "Grateful Deploy"
    assert_select ".topbar__brand", "Grateful Deploy"
  end

  test "shows a card per app with version, health, memory and last deploy" do
    sign_in_as users(:owner)

    get root_path

    assert_response :success
    assert_select ".app-card", 2
    assert_select "#card_app_#{apps(:storefront).id}" do
      assert_select ".app-card__name", "storefront"
      assert_select ".app-card__version", "f595690"
      assert_select ".health--up", "Healthy"
      assert_select ".app-card__memory", "352 MB"
      assert_select ".app-card__deploy", /succeeded/
      assert_select "a[href=?]", "http://storefront.example.com", text: "storefront.example.com"
    end
    assert_select "#card_app_#{apps(:incidents).id} .health--down", "Down"
  end

  test "an app that was never checked says so" do
    StatusSnapshot.delete_all
    sign_in_as users(:owner)

    get root_path

    assert_select "#card_app_#{apps(:storefront).id} .health--unknown", "Not checked yet"
  end

  test "app page shows status, domains and how kamal is run" do
    sign_in_as users(:owner)

    get app_path(apps(:storefront))

    assert_response :success
    assert_select "h1", /storefront/
    assert_select ".health--up", "Healthy"
    assert_select ".app-facts", /f595690/
    assert_select ".app-facts", %r{bin/kamal deploy -d nbg}
    assert_select ".app-facts a[href=?]", "http://storefront.example.com"
  end

  test "apps outside the current organization are not found" do
    other = Organization.create!(name: "Other")
    stranger = other.servers.create!(name: "x", host: "198.51.100.9")
                    .apps.create!(name: "x", repo_path: "/tmp/x", service: "x", destination: "x")
    sign_in_as users(:owner)

    get app_path(stranger)

    assert_response :not_found
  end

  test "app names on cards link to the app page" do
    sign_in_as users(:owner)

    get root_path

    assert_select ".app-card__name a[href=?]", app_path(apps(:storefront)), text: "storefront"
  end

  test "app page lists deploy history, newest first, linking to each log" do
    newer = apps(:storefront).deploys.create!(kind: "rollback", version: "0041612", status: "failed")
    sign_in_as users(:owner)

    get app_path(apps(:storefront))

    assert_select ".deploy-history tbody tr", 2
    assert_select ".deploy-history tbody tr:first-child" do
      assert_select "a[href=?]", app_deploy_path(apps(:storefront), newer)
      assert_select ".status--failed"
      assert_select "td", /rollback/
    end
    assert_select ".deploy-history tbody tr:last-child", /7d1e0f2.*Tighten race list layout/m
    assert_select ".deploy-history tbody tr:last-child", /3 minutes/
  end

  test "app page says when there is no deploy history yet" do
    sign_in_as users(:owner)

    get app_path(apps(:incidents))

    assert_select ".deploy-history", /No deploys from Grateful Deploy yet/
  end

  test "the running version survives a failed status check, on the card and the app page" do
    app = apps(:storefront)
    app.status_snapshots.create!(error: "ssh: communication with agent failed", checked_at: Time.current)
    sign_in_as users(:owner)

    get root_path
    assert_select "#card_app_#{app.id} .app-card__version", "f595690"

    get app_path(app)
    assert_select ".app-facts dd.mono", "f595690"
  end

  test "deploy history shows exact times" do
    app = apps(:storefront)
    app.deploys.create!(kind: "deploy", status: "succeeded", created_at: Time.zone.local(2026, 10, 15, 16, 42))
    sign_in_as users(:owner)

    get app_path(app)

    assert_select ".deploy-history a", text: "Oct 15, 16:42"
    assert_select ".deploy-history a", text: /ago/, count: 0
  end

  test "no page says how long ago something happened; times are exact" do
    app = apps(:storefront)
    app.deploys.create!(kind: "deploy", status: "succeeded")
    app.status_snapshots.update_all(checked_at: 10.minutes.ago)
    app.status_snapshots.create!(error: "ssh: communication with agent failed", checked_at: Time.current)
    sign_in_as users(:owner)

    [ root_path, app_path(app), servers_path ].each do |path|
      get path
      assert_no_match(/\bago\b/, response.body.gsub(/<[^>]+>/, " "), "#{path} says 'ago'")
    end
  end

  test "a running app with no domain to check shows a muted note, not a red error" do
    sign_in_as users(:owner)
    apps(:storefront).status_snapshots.create!(container_state: "running", version: "a" * 40, error: HealthCheck::NO_DOMAIN, checked_at: 1.second.from_now)

    get root_path

    assert_select "#card_app_#{apps(:storefront).id} .health--unknown", "Running · not health-checked"
    assert_select "#card_app_#{apps(:storefront).id} .app-card__note", HealthCheck::NO_DOMAIN
    assert_select "#card_app_#{apps(:storefront).id} .app-card__error", false
  end

  test "the app page shows the env values Kamal runs with, and which aren't set yet" do
    sign_in_as users(:owner)
    apps(:storefront).update!(kamal_env: { "STOREFRONT_SERVER" => "203.0.113.30", "STOREFRONT_DOMAIN" => nil })

    get app_path(apps(:storefront))

    assert_select ".app-facts dd", "STOREFRONT_SERVER=203.0.113.30 STOREFRONT_DOMAIN=(not set) bin/kamal deploy -d nbg"
  end

  test "the deploy history marks deploys made outside Grateful Deploy" do
    sign_in_as users(:owner)
    apps(:storefront).record_outside_deploy!(command: "deploy", version: "3f82b485b194940a926be0ddfdd830458db0c220", runtime: "40")

    get app_path(apps(:storefront))

    assert_select ".deploy-history td", "deploy · outside Grateful Deploy"
  end
end
