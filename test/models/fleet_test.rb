require "test_helper"

class FleetTest < ActiveSupport::TestCase
  setup { @path = file_fixture("fleet.yml") }

  test "imports servers and their apps" do
    Fleet.import(@path, organization: organizations(:primary))

    server = organizations(:primary).servers.find_by!(name: "lab")
    assert_equal "198.51.100.7", server.host
    assert_equal 8080, server.proxy_http_port

    blog = server.apps.find_by!(name: "blog")
    assert blog.destination_mode?
    assert_equal "lab", blog.destination
    assert_equal File.expand_path("~/Work/blog"), blog.repo_path
    assert_equal [ "blog.example.com" ], blog.domains

    shop = server.apps.find_by!(name: "shop")
    assert shop.config_file_mode?
    assert shop.global?
    assert_equal "/health", shop.health_path
    assert_equal({ "SHOP_SERVER" => "198.51.100.7", "SHOP_DOMAIN" => nil }, shop.kamal_env)
    assert_equal({}, blog.kamal_env)
  end

  test "importing twice updates instead of duplicating" do
    2.times { Fleet.import(@path, organization: organizations(:primary)) }

    assert_equal 1, organizations(:primary).servers.where(name: "lab").count
    assert_equal 2, organizations(:primary).servers.find_by!(name: "lab").apps.count
  end

  test "an app listed under another server moves there, keeping its history" do
    Fleet.import(@path, organization: organizations(:primary))
    blog = organizations(:primary).servers.find_by!(name: "lab").apps.find_by!(name: "blog")
    deploy = blog.deploys.create!(kind: "deploy", triggered_by: "ui")
    data = YAML.load_file(@path)
    data["servers"]["home"] = { "host" => "127.0.0.1", "ssh_user" => "joel",
                                "apps" => { "blog" => data["servers"]["lab"]["apps"].delete("blog") } }
    Fleet.new(data, organizations(:primary)).import

    moved = organizations(:primary).servers.find_by!(name: "home").apps.find_by!(name: "blog")
    assert_equal blog.id, moved.id
    assert_equal [ deploy ], moved.deploys.to_a
    assert_equal [ "shop" ], organizations(:primary).servers.find_by!(name: "lab").apps.pluck(:name)
  end

  test "an app whose kamal_env is removed from the file gets none, so no stale value reaches Kamal" do
    Fleet.import(@path, organization: organizations(:primary))
    data = YAML.load_file(@path)
    data["servers"]["lab"]["apps"]["shop"].delete("kamal_env")
    Fleet.new(data, organizations(:primary)).import

    assert_equal({}, organizations(:primary).servers.find_by!(name: "lab").apps.find_by!(name: "shop").kamal_env)
  end
end
