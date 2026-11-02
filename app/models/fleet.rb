# Loads servers and apps from a versioned YAML file (config/fleet.yml).
# Upserts by name; never deletes anything that's missing from the file. An app
# the file lists under a different server than before moves there, keeping its
# deploys and checks.
class Fleet
  def self.import(path, organization:)
    new(YAML.load_file(path), organization).import
  end

  def initialize(data, organization)
    @data = data
    @organization = organization
  end

  def import
    @data.fetch("servers").each do |name, attrs|
      attrs = attrs.dup
      apps = attrs.delete("apps") || {}
      server = @organization.servers.find_or_initialize_by(name: name)
      server.update!(attrs)
      apps.each { |app_name, app_attrs| import_app(server, app_name, app_attrs) }
    end
  end

  private

  def import_app(server, name, attrs)
    attrs = attrs.merge(
      "repo_path" => File.expand_path(attrs.fetch("repo_path")),
      "kamal_mode" => attrs.key?("config_file") ? "config_file" : "destination",
      # Removing kamal_env from the file clears it, so a stale value never reaches Kamal.
      "kamal_env" => attrs["kamal_env"] || {}
    )
    (server.apps.find_by(name: name) || moved_app(name) || server.apps.new(name: name)).update!(attrs.merge("server" => server))
  end

  # The app of that name on a server whose entry in the file no longer lists it.
  def moved_app(name)
    App.joins(:server).where(name: name, servers: { organization_id: @organization.id })
      .find { |app| !@data.fetch("servers").dig(app.server.name, "apps")&.key?(name) }
  end
end
