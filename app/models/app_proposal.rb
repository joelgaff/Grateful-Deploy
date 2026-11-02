# One scanned Kamal config on the Add app page: whether it can be added, and
# the app it becomes. Repo path, config and service come from the scan; the
# form only names the app, picks a server when the ERB decides it, and fills
# in domains, the health check and the config's own ENV settings.
class AppProposal
  attr_reader :config

  def initialize(organization, config)
    @organization = organization
    @config = config
  end

  # The known server the config deploys to; nil when the ERB fills it in.
  def server
    @server ||= @organization.servers.find_by(host: config.hosts) if config.hosts.any?
  end

  def server_choice? = config.hosts.empty? && config.hosts_from_erb?

  # An app already deploying this service from this repo, by any of its configs.
  def existing_app
    @existing_app ||= @organization.apps.find_by(repo_path: config.repo.path, service: config.service) if config.service
  end

  def ready? = blocked_reason.nil?

  def blocked_reason
    if config.error
      config.error
    elsif existing_app
      "Already added as #{existing_app.name} on #{existing_app.server.name}"
    elsif config.rails_default?
      "Rails' generated config: it still deploys to #{KamalRepo::RAILS_DEFAULT_HOST}"
    elsif config.hosts.any? && server.nil?
      "Deploys to #{config.hosts.to_sentence}, a server Grateful Deploy doesn't know. Add it under servers in config/fleet.yml first."
    elsif config.hosts.empty? && !config.hosts_from_erb?
      "#{config.id} names no servers"
    end
  end

  def defaults
    { name: config.service, domains: config.domains.join(", "), health_path: config.health_path, health_https: config.ssl == true }
  end

  def build(name:, server_id: nil, domains: nil, health_path: nil, health_https: nil, kamal_env: {})
    App.new(
      server: server || @organization.servers.find_by(id: server_id), name: name,
      repo_path: config.repo.path, kamal_mode: config.kamal_mode, config_file: config.config_file,
      destination: config.destination, kamal_binary: config.kamal_binary, service: config.service,
      domains: domains.nil? ? config.domains : domains.to_s.split(/[\s,]+/).compact_blank,
      health_path: health_path.presence || config.health_path,
      health_https: health_https.nil? ? config.ssl == true : ActiveModel::Type::Boolean.new.cast(health_https),
      kamal_env: config.env_names.index_with { |env_name| kamal_env.to_h[env_name].presence }
    )
  end
end
