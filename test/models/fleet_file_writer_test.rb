require "test_helper"

# Add app writes the new app into config/fleet.yml under its server, as text,
# so the file's comments and layout stay as they were; the result imports.
class FleetFileWriterTest < ActiveSupport::TestCase
  setup do
    @file = Tempfile.new([ "fleet", ".yml" ])
    File.write(@file.path, <<~YAML)
      # The fleet.
      servers:
        lab:
          host: 198.51.100.7
          # Proxy on 8080.
          proxy_http_port: 8080
          apps:
            blog:
              # The blog.
              repo_path: ~/Work/blog
              destination: lab
              service: blog
              domains: [blog.example.com]

        home:
          host: 127.0.0.1
          ssh_user: joel
    YAML
    @app = App.new(name: "shop", repo_path: File.expand_path("~/Work/shop"), kamal_mode: "config_file",
                   config_file: "config/deploy.yml", kamal_binary: "global", service: "shop", health_path: "/health",
                   health_https: true, kamal_env: { "SHOP_DOMAIN" => "shop.example.com", "SHOP_TLS" => "false" },
                   domains: %w[shop.example.com www.shop.example.com])
  end

  teardown { @file.close! }

  def imported
    Fleet.import(@file.path, organization: organizations(:primary))
    organizations(:primary).servers
  end

  test "adds the app after the server's last app, keeping every comment" do
    FleetFile.new(@file.path).add(@app, server_name: "lab")
    text = File.read(@file.path)

    assert_includes text, <<~YAML.gsub(/^(?=.)/, "  ")
            blog:
              # The blog.
              repo_path: ~/Work/blog
              destination: lab
              service: blog
              domains: [blog.example.com]
            shop:
              repo_path: ~/Work/shop
              config_file: config/deploy.yml
              kamal_binary: global
              service: shop
              health_path: /health
              health_https: true
              kamal_env:
                SHOP_DOMAIN: shop.example.com
                SHOP_TLS: 'false'
              domains: [shop.example.com, www.shop.example.com]

        home:
    YAML
    assert_includes text, "# The fleet.\n"
    assert_includes text, "    # Proxy on 8080.\n"
  end

  test "the written entry imports as the same app" do
    FleetFile.new(@file.path).add(@app, server_name: "lab")
    shop = imported.find_by!(name: "lab").apps.find_by!(name: "shop")

    %w[repo_path kamal_mode config_file kamal_binary service health_path health_https kamal_env domains].each do |attribute|
      assert_equal @app.public_send(attribute), shop.public_send(attribute), attribute
    end
  end

  test "a server without apps gets an apps list; a destination app writes only what differs from the defaults" do
    app = App.new(name: "notes", repo_path: "/srv/notes", kamal_mode: "destination", destination: "home",
                  kamal_binary: "bundled", service: "notes", health_path: "/up", health_https: false, kamal_env: {}, domains: [])
    FleetFile.new(@file.path).add(app, server_name: "home")

    assert_equal <<~YAML.gsub(/^(?=.)/, "  "), File.read(@file.path).lines.last(9).join
        home:
          host: 127.0.0.1
          ssh_user: joel
          apps:
            notes:
              repo_path: /srv/notes
              destination: home
              service: notes
              domains: []
    YAML
    assert_equal "home", imported.find_by!(name: "home").apps.find_by!(name: "notes").destination
  end

  test "refuses an app the file already lists, or a server it doesn't" do
    @app.name = "blog"
    assert_raises(FleetFile::Error) { FleetFile.new(@file.path).add(@app, server_name: "lab") }
    @app.name = "shop"
    assert_raises(FleetFile::Error) { FleetFile.new(@file.path).add(@app, server_name: "nbg") }
    assert_not_includes File.read(@file.path), "shop"
  end

  test "adds a server at the end of the servers list, writing only what differs from the defaults" do
    server = Server.new(name: "box", host: "box.example.com", ssh_user: "deploy", region: "Basement",
                        proxy_http_port: 80, proxy_https_port: 8443, notes: "The old desktop")
    FleetFile.new(@file.path).add_server(server)

    assert_equal <<~YAML.gsub(/^(?=.)/, "  "), File.read(@file.path).lines.last(10).join
        home:
          host: 127.0.0.1
          ssh_user: joel

        box:
          host: box.example.com
          ssh_user: deploy
          region: Basement
          proxy_https_port: 8443
          notes: The old desktop
    YAML
    assert_includes File.read(@file.path), "    # Proxy on 8080.\n"
    box = imported.find_by!(name: "box")
    %w[host ssh_user region proxy_http_port proxy_https_port notes].each do |attribute|
      assert_equal server.public_send(attribute), box.public_send(attribute), attribute
    end
  end

  test "a root server writes just its host" do
    FleetFile.new(@file.path).add_server(Server.new(name: "bare", host: "198.51.100.8"))

    assert_equal "\n  bare:\n    host: 198.51.100.8\n", File.read(@file.path).lines.last(3).join
    assert_equal "root", imported.find_by!(name: "bare").ssh_user
  end

  test "refuses a server the file already lists" do
    before = File.read(@file.path)
    assert_raises(FleetFile::Error) { FleetFile.new(@file.path).add_server(Server.new(name: "home", host: "198.51.100.8")) }
    assert_equal before, File.read(@file.path)
  end
end
