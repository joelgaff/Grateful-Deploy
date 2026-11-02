require "test_helper"

# Add app: one scanned Kamal config, what stands in the way of adding it, and
# the app it becomes. The server is the known one the config deploys to;
# a config that deploys to a server Grateful Deploy doesn't know can't be added.
class AppProposalTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir
    @organization = organizations(:primary)
    @nbg = servers(:nbg)
  end

  teardown { FileUtils.rm_rf(@root) }

  def repo(path, deploy_yml)
    FileUtils.mkdir_p(File.join(@root, path, "config"))
    File.write(File.join(@root, path, "config/deploy.yml"), deploy_yml)
    KamalRepo.find(@root, path).configs.first
  end

  def proposal(config) = AppProposal.new(@organization, config)

  def shop_yml(host = @nbg.host) = "service: shop\nservers: [#{host}]\nproxy:\n  ssl: true\n  hosts: [shop.example.com]\n"

  test "a config for a known server is ready, on that server" do
    shop = proposal(repo("shop", shop_yml))

    assert shop.ready?
    assert_equal @nbg, shop.server
    assert_nil shop.blocked_reason
  end

  test "a config for a server Grateful Deploy doesn't know says so and can't be added" do
    shop = proposal(repo("shop", shop_yml("198.51.100.99")))

    assert_not shop.ready?
    assert_nil shop.server
    assert_equal "Deploys to 198.51.100.99, a server Grateful Deploy doesn't know. Add it under servers in config/fleet.yml first.", shop.blocked_reason
  end

  test "an untouched Rails default or an unreadable config can't be added" do
    assert_match(/Rails' generated config/, proposal(repo("fresh", shop_yml("192.168.0.1"))).blocked_reason)
    assert_match(/isn't valid YAML/, proposal(repo("broken", "service: [\n")).blocked_reason)
  end

  test "a config already deploying an app here is marked added, with that app" do
    config = repo("shop", shop_yml)
    app = @nbg.apps.create!(name: "shop", repo_path: config.repo.path, kamal_mode: "config_file", config_file: "config/deploy.yml", service: "shop")

    assert_equal app, proposal(config).existing_app
    assert_equal "Already added as shop on nbg", proposal(config).blocked_reason
  end

  # notes deploys with -d nbg; its deploy.nbg.yml read alone would be the same app twice.
  test "another config of a repo already deploying that service is marked added too" do
    config = repo("shop", shop_yml)
    app = @nbg.apps.create!(name: "shop", repo_path: config.repo.path, kamal_mode: "destination", destination: "nbg", service: "shop")

    assert_equal app, proposal(config).existing_app
  end

  test "a server the ERB fills in is picked from the known servers" do
    shop = proposal(repo("home", "service: home\nservers: [<%= ENV.fetch(\"HOME_SERVER\") %>]\n"))

    assert shop.ready?
    assert_nil shop.server
    assert shop.server_choice?
  end

  test "the app it builds: the config's settings, the form's choices, only the config's ENV names" do
    config = repo("home", "service: home\nservers: [<%= ENV.fetch(\"HOME_SERVER\") %>]\nproxy:\n  hosts: [home.example.com]\n")
    app = proposal(config).build(name: "home", server_id: @nbg.id, domains: "home.example.com, www.home.example.com",
                                 health_path: "/up", health_https: "1",
                                 kamal_env: { "HOME_SERVER" => "203.0.113.10", "PATH" => "/tmp" })

    assert app.valid?, app.errors.full_messages.to_sentence
    assert_equal [ @nbg, config.repo.path, "config_file", "config/deploy.yml", "global", "home" ],
                 [ app.server, app.repo_path, app.kamal_mode, app.config_file, app.kamal_binary, app.service ]
    assert_equal %w[home.example.com www.home.example.com], app.domains
    assert app.health_https?
    assert_equal({ "HOME_SERVER" => "203.0.113.10" }, app.kamal_env)
  end

  test "the form can't move a config to an unknown server, or reuse an app name" do
    shop = proposal(repo("shop", shop_yml))
    other = @organization.servers.create!(name: "other", host: "198.51.100.1")

    assert_equal @nbg, shop.build(name: "shop", server_id: other.id).server
    assert_not shop.build(name: apps(:storefront).name).valid?
  end

  # Fleet.import matches an app by name when it moves between servers.
  test "an app name is used once across all servers" do
    home = proposal(repo("home", "service: home\nservers: [<%= ENV.fetch(\"HOME_SERVER\") %>]\n"))
    other = @organization.servers.create!(name: "other", host: "198.51.100.1")
    app = home.build(name: apps(:storefront).name, server_id: other.id)

    assert_not app.valid?
    assert_includes app.errors[:name], "is already used by an app on nbg"
  end

  test "the form's defaults come from the config" do
    shop = proposal(repo("shop", shop_yml))

    assert_equal [ "shop", "shop.example.com", "/up", true ], shop.defaults.values_at(:name, :domains, :health_path, :health_https)
  end
end
