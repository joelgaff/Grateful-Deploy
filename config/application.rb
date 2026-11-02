require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module GratefulDeploy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks mail_delivery.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Grateful Deploy runs on your laptop, so times show in the laptop's zone.
    config.time_zone = ENV["TZ"].presence || begin
      File.readlink("/etc/localtime").split("zoneinfo/").last
    rescue SystemCallError
      "UTC"
    end
    # Add app scans this folder for repos with Kamal config, and writes the
    # apps it adds into this fleet.yml (in production, a link bin/release makes
    # to the source checkout's).
    config.x.repos_root = ENV.fetch("GRATEFUL_DEPLOY_REPOS_ROOT", File.expand_path("~/Work"))
    config.x.fleet_file = ENV.fetch("GRATEFUL_DEPLOY_FLEET_FILE", Rails.root.join("config/fleet.yml").to_s)
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
