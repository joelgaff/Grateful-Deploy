require "test_helper"

# Finding apps to add: the repos under the repos folder that have Kamal config,
# and what their config says. The ERB in a config is never run; values it
# fills in are reported as unknown, and the ENV names it reads become kamal_env.
class KamalRepoTest < ActiveSupport::TestCase
  setup { @root = Dir.mktmpdir }
  teardown { FileUtils.rm_rf(@root) }

  def repo(path, files)
    files.each do |name, body|
      file = File.join(@root, path, name)
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, body)
    end
    File.chmod(0o755, File.join(@root, path, "bin/kamal")) if files.key?("bin/kamal")
  end

  BLOG = <<~YAML.freeze
    service: blog
    image: joel/blog
    servers:
      web:
        - 203.0.113.10
      job:
        hosts:
          - 203.0.113.10
        cmd: bin/jobs
    proxy:
      ssl: true
      host: blog.example.com
      healthcheck:
        path: /health
  YAML

  test "finds the repos with Kamal config, one and two folders down, by their path under the root" do
    repo("blog", "config/deploy.yml" => BLOG)
    repo("vendors/rails", "config/deploy.yml" => BLOG)
    repo("notes", "README.md" => "no kamal here")

    assert_equal %w[blog vendors/rails], KamalRepo.scan(@root).map(&:key)
    assert_equal File.join(@root, "vendors/rails"), KamalRepo.find(@root, "vendors/rails").path
  end

  test "only a scanned repo can be found, so a path from a form can't point anywhere else" do
    repo("blog", "config/deploy.yml" => BLOG)

    assert_raises(KamalRepo::NotFound) { KamalRepo.find(@root, "../etc") }
    assert_raises(KamalRepo::NotFound) { KamalRepo.find(@root, "notes") }
  end

  test "reads the service, web hosts, domain, SSL and health path" do
    repo("blog", "config/deploy.yml" => BLOG, "bin/kamal" => "#!/bin/sh")
    config = KamalRepo.find(@root, "blog").configs.sole

    assert_equal [ "config_file", "config/deploy.yml", nil ], [ config.kamal_mode, config.config_file, config.destination ]
    assert_equal "blog", config.service
    assert_equal [ "203.0.113.10" ], config.hosts
    assert_equal [ "blog.example.com" ], config.domains
    assert_equal true, config.ssl
    assert_equal "/health", config.health_path
    assert_equal "bundled", config.kamal_binary
    assert_nil config.error
  end

  test "without bin/kamal it uses the global kamal, and the health path defaults to /up" do
    repo("blog", "config/deploy.yml" => "service: blog\nservers: [203.0.113.10]\nproxy:\n  hosts: [a.example.com, b.example.com]\n")
    config = KamalRepo.find(@root, "blog").configs.sole

    assert_equal "global", config.kamal_binary
    assert_equal "/up", config.health_path
    assert_equal %w[a.example.com b.example.com], config.domains
    assert_equal false, config.ssl
  end

  test "a destination file is offered merged into deploy.yml (-d) and on its own (-c)" do
    repo("notes", "config/deploy.yml" => BLOG, "config/deploy.nbg.yml" => "servers:\n  web:\n    - 203.0.113.30\nproxy:\n  host: notes.example.com\n")
    merged, alone = KamalRepo.find(@root, "notes").configs.drop(1)

    assert_equal [ "destination", "nbg", [ "203.0.113.30" ], "blog", true ], [ merged.kamal_mode, merged.destination, merged.hosts, merged.service, merged.ssl ]
    assert_equal [ "config_file", "config/deploy.nbg.yml", nil ], [ alone.kamal_mode, alone.config_file, alone.service ]
  end

  test "values the ERB fills in are unknown, and the plain ENV names it reads become kamal_env; secrets stay in .env" do
    repo("home", "config/deploy.yml" => <<~YAML)
      <% server = ENV.fetch("HOME_SERVER", "server.example.com") %>
      <%# a comment %>
      <% tunnel = ENV["CLOUDFLARE_TUNNEL_TOKEN"].to_s.strip != "" %>
      service: home
      servers:
        web:
          - <%= server %>
      proxy:
        ssl: <%= ENV.fetch("HOME_TLS", "true") != "false" %>
        host: <%= ENV.fetch("HOME_DOMAIN") %>
      <% if tunnel %>
      accessories:
        tunnel:
          host: <%= server %>
      <% end %>
    YAML
    config = KamalRepo.find(@root, "home").configs.sole

    assert_equal "home", config.service
    assert_equal [], config.hosts
    assert config.hosts_from_erb?
    assert_equal [], config.domains
    assert_nil config.ssl
    assert_equal %w[HOME_SERVER HOME_TLS HOME_DOMAIN], config.env_names
  end

  test "an untouched Rails default config is marked, so it isn't offered as ready" do
    repo("fresh", "config/deploy.yml" => "service: fresh\nservers:\n  web:\n    - 192.168.0.1\nproxy:\n  ssl: true\n  host: app.example.com\n")

    assert KamalRepo.find(@root, "fresh").configs.sole.rails_default?
    assert_not KamalRepo.find(@root, "fresh").configs.sole.tap { it.hosts.replace([ "203.0.113.10" ]) }.rails_default?
  end

  test "a config that isn't valid YAML says why instead of failing the list" do
    repo("broken", "config/deploy.yml" => "service: [unclosed\n")
    config = KamalRepo.find(@root, "broken").configs.sole

    assert_match(/YAML/i, config.error)
    assert_nil config.service
  end

  test "each config has an id to pick it by, and only those ids are found" do
    repo("notes", "config/deploy.yml" => BLOG, "config/deploy.nbg.yml" => "servers: [203.0.113.30]\n")
    notes = KamalRepo.find(@root, "notes")

    assert_equal %w[config/deploy.yml -d\ nbg config/deploy.nbg.yml], notes.configs.map(&:id)
    assert_equal "nbg", notes.config("-d nbg").destination
    assert_raises(KamalRepo::NotFound) { notes.config("config/../../secrets.yml") }
  end

  test "proxy hosts win over a host left in deploy.yml, and real domains come before sslip.io test hosts" do
    repo("shop", "config/deploy.yml" => "service: shop\nservers: [203.0.113.10]\nproxy:\n  host: app.example.com\n",
                 "config/deploy.nbg.yml" => "proxy:\n  hosts: [shop.203-0-113-10.sslip.io, shop.example.com]\n")

    assert_equal %w[shop.example.com shop.203-0-113-10.sslip.io], KamalRepo.find(@root, "shop").config("-d nbg").domains
  end

  test "a file that only adds to deploy.yml, with no service of its own, says so" do
    repo("shop", "config/deploy.yml" => BLOG, "config/deploy.nbg.yml" => "servers: [203.0.113.30]\n")

    assert_nil KamalRepo.find(@root, "shop").config("-d nbg").error
    assert_equal "config/deploy.nbg.yml has no service, so it only adds to config/deploy.yml (use -d nbg)",
                 KamalRepo.find(@root, "shop").config("config/deploy.nbg.yml").error
  end
end
