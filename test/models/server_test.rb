require "test_helper"

class ServerTest < ActiveSupport::TestCase
  test "valid with a name and host in an organization" do
    server = organizations(:primary).servers.new(name: "ash", host: "203.0.113.20")

    assert server.valid?
    assert_equal "root", server.ssh_user
    assert_equal 80, server.proxy_http_port
  end

  test "requires a name and host" do
    server = organizations(:primary).servers.new

    assert_not server.valid?
    assert_includes server.errors[:name], "can't be blank"
    assert_includes server.errors[:host], "can't be blank"
  end

  test "names are unique within an organization" do
    server = organizations(:primary).servers.new(name: servers(:nbg).name, host: "203.0.113.11")

    assert_not server.valid?
    assert_includes server.errors[:name], "has already been taken"
  end
end
