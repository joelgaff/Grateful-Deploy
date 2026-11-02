require "test_helper"

# Production settings that only matter once Grateful Deploy runs as a service.
class ProductionConfigTest < ActiveSupport::TestCase
  def production_db_configs
    yaml = ERB.new(Rails.root.join("config/database.yml").read).result
    ActiveRecord::DatabaseConfigurations.new(YAML.safe_load(yaml, aliases: true)).configs_for(env_name: "production")
  end

  def queue_threads
    yaml = ERB.new(Rails.root.join("config/queue.yml").read).result
    YAML.safe_load(yaml, aliases: true).fetch("production").fetch("workers").sum { it.fetch("threads") }
  end

  test "every production database pool fits Puma's threads plus all job threads" do
    puma_threads = Integer(ENV.fetch("RAILS_MAX_THREADS", 3))
    needed = puma_threads + queue_threads + 2 # + Solid Queue's dispatcher and scheduler

    production_db_configs.each do |config|
      assert_operator config.max_connections, :>=, needed, "#{config.name} pool"
    end
  end

  test "login codes are filtered from logs, like passwords and tokens" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    assert_equal({ "identity_id" => "7", "code" => "[FILTERED]" }, filter.filter("identity_id" => "7", "code" => "123456"))
  end

  test "the service runs production from its own checkout, on 127.0.0.1:3100 only, with jobs inside Puma" do
    unit = Rails.root.join("config/systemd/grateful-deploy.service").read

    assert_includes unit, "WorkingDirectory=%h/.local/share/grateful-deploy"
    assert_includes unit, "Environment=RAILS_ENV=production"
    assert_includes unit, "Environment=SOLID_QUEUE_IN_PUMA=1"
    assert_match %r{^ExecStart=/usr/bin/mise exec -- bin/rails server -b 127\.0\.0\.1 -p 3100$}, unit
  end

  test "the dev server defaults to 3101, so it never takes production's 3100" do
    assert_includes Rails.root.join("bin/dev").read, %(ENV["PORT"] ||= "3101")
  end

  test "production answers only to 127.0.0.1, localhost and names set on the machine, so a rebinding web page can't reach it" do
    production = Rails.root.join("config/environments/production.rb").read

    assert_match(/^  config\.hosts = \[ "127\.0\.0\.1", "localhost", \*ENV\.fetch\("GRATEFUL_DEPLOY_HOSTS", ""\)/, production)
  end

  test "bin/release only calls rake tasks that exist, so a rename can't break the idle check" do
    Rails.application.load_tasks
    called = Rails.root.join("bin/release").read.scan(/bin\/rails (\w+:\w+)/).flatten

    assert_includes called, "grateful_deploy:assert_idle"
    called.each { |task| assert Rake::Task.task_defined?(task), "bin/release calls #{task}, which isn't defined" }
  end
end
