require "test_helper"

# Add server: the servers page links to a form; saving adds the server here,
# checks it over SSH, and writes it into config/fleet.yml to review.
class ServerAdditionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:owner)
    @fleet = Tempfile.new([ "fleet", ".yml" ])
    File.write(@fleet.path, "servers:\n  nbg:\n    host: #{servers(:nbg).host}\n")
    @setting = Rails.configuration.x.fleet_file
    Rails.configuration.x.fleet_file = @fleet.path
  end

  teardown do
    Rails.configuration.x.fleet_file = @setting
    @fleet.close!
  end

  def box_params(**server) = { server: { name: "box", host: "box.example.com", ssh_user: "deploy", region: "Basement",
                                         proxy_http_port: "80", proxy_https_port: "443", notes: "", **server } }

  test "the servers page links to Add server" do
    get servers_path
    assert_select "a[href=?]", new_server_path, text: "Add server"
  end

  test "the form starts from Kamal's defaults" do
    get new_server_path

    assert_response :success
    assert_select "input[name='server[ssh_user]'][value=root]"
    assert_select "input[name='server[proxy_http_port]'][value='80']"
    assert_select "input[name='server[proxy_https_port]'][value='443']"
  end

  test "saving adds the server, checks it, and writes it into config/fleet.yml" do
    assert_difference -> { organizations(:primary).servers.count } do
      assert_enqueued_with(job: RefreshStatusJob, args: [ { force: true } ]) do
        post servers_path, params: box_params
      end
    end

    box = organizations(:primary).servers.find_by!(name: "box")
    assert_equal [ "box.example.com", "deploy", "Basement" ], [ box.host, box.ssh_user, box.region ]
    assert_redirected_to servers_path
    assert_match /Added box.*review it/, flash[:notice]
    assert_includes File.read(@fleet.path), "  box:\n    host: box.example.com\n    ssh_user: deploy\n"
  end

  test "says so when config/fleet.yml can't be written, but keeps the server" do
    File.write(@fleet.path, "servers:\n  box:\n    host: other.example.com\n")

    post servers_path, params: box_params

    assert organizations(:primary).servers.exists?(name: "box")
    assert_match /couldn't write config\/fleet.yml/, flash[:alert]
  end

  test "a name already taken shows the form again" do
    assert_no_difference -> { Server.count } do
      post servers_path, params: box_params(name: "nbg")
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors", /Name has already been taken/
  end

  # The host and user go straight into ssh's arguments: nothing that reads as an option or a second word.
  test "refuses a host or ssh user that isn't a plain name" do
    [ { host: "" }, { host: "-oProxyCommand=touch x" }, { host: "box example.com" }, { ssh_user: "-oProxyCommand=x" },
      { ssh_user: "joel@box" }, { proxy_http_port: "0" }, { proxy_https_port: "70000" } ].each do |bad|
      assert_no_difference(-> { Server.count }, bad.inspect) { post servers_path, params: box_params(**bad) }
      assert_response :unprocessable_entity
    end
    assert_equal "servers:\n  nbg:\n    host: #{servers(:nbg).host}\n", File.read(@fleet.path)
  end

  test "IPv4 and IPv6 hosts are fine" do
    post servers_path, params: box_params(host: "198.51.100.20")
    post servers_path, params: box_params(name: "six", host: "2001:db8::1")
    assert_equal [ "198.51.100.20", "2001:db8::1" ], Server.where(name: %w[box six]).order(:name).pluck(:host)
  end

  test "the server belongs to the signed-in organization, whatever the form says" do
    other = Organization.create!(name: "Other")
    post servers_path, params: box_params(organization_id: other.id)
    assert_equal organizations(:primary), Server.find_by!(name: "box").organization
  end
end
