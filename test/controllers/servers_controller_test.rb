require "test_helper"

class ServersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:owner) }

  test "shows RAM, swap and disk for each server" do
    get servers_path

    assert_response :success
    assert_select "#panel_server_#{servers(:nbg).id}" do
      assert_select "h2", /nbg/
      assert_select ".meter--memory", /3.47 GB of 7.56 GB/
      assert_select ".meter--memory .meter__bar[style*=?]", "width: 46%"
      assert_select ".meter--disk", /10.6 GB of 74.8 GB/
      assert_select ".meter--disk .meter__bar[style*=?]", "width: 14%"
      assert_select ".meter--swap", /424 KB of 2 GB/
      assert_select ".meter--load", /0.21 · 0.14 · 0.10 on 4 CPUs/
      assert_select ".meter--load .meter__bar[style*=?]", "width: 5%"
    end
  end

  test "lists containers, linking app containers to their app page" do
    get servers_path

    assert_select ".containers tbody tr", 2
    assert_select ".containers a[href=?]", app_path(apps(:storefront)), text: "storefront"
    assert_select ".containers td.mono", "f595690"
    assert_select ".containers", /kamal-proxy/
    assert_select ".containers", /352 MB/
  end

  test "says when a server has not been checked yet" do
    ServerSnapshot.delete_all

    get servers_path

    assert_select "#panel_server_#{servers(:nbg).id}", /Not checked yet/
  end

  test "shows an ssh error from the last check" do
    servers(:nbg).server_snapshots.create!(error: "SSH agent refused. Unlock 1Password (SSH agent) and try again.", checked_at: Time.current)

    get servers_path

    assert_select ".app-card__error", /Unlock 1Password/
  end

  test "the nav links to servers" do
    get root_path

    assert_select ".topbar__nav a[href=?]", servers_path, text: "Servers"
  end

  test "other organizations' servers are not shown" do
    Organization.create!(name: "Other").servers.create!(name: "stranger", host: "198.51.100.9")

    get servers_path

    assert_select "h2", text: /stranger/, count: 0
  end
end
