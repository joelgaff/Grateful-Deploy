# A repo under the repos folder (~/Work) with Kamal config, found by scanning,
# never from a path someone typed: Add app offers only what scan finds.
# Its configs are read as YAML with the ERB left unrun; whatever the ERB
# fills in is unknown, and the ENV names it reads become kamal_env.
class KamalRepo
  class NotFound < StandardError; end

  CONFIG_GLOB = "config/deploy{,.*}.yml".freeze
  # Rails 8's generated deploy.yml deploys here until someone sets a real server.
  RAILS_DEFAULT_HOST = "192.168.0.1".freeze

  attr_reader :root, :key, :path

  def self.scan(root)
    root = File.expand_path(root)
    %w[* */*].flat_map { |depth| Dir.glob(File.join(root, depth, "config/deploy.yml")) + Dir.glob(File.join(root, depth, "config/deploy.*.yml")) }
      .map { |file| File.dirname(file, 2) }.uniq.sort
      .map { |path| new(root, path.delete_prefix("#{root}/")) }
  end

  def self.find(root, key)
    scan(root).find { |repo| repo.key == key } or raise NotFound, "No Kamal repo #{key.inspect} under #{root}"
  end

  def initialize(root, key)
    @root = root
    @key = key
    @path = File.join(root, key)
  end

  # deploy.yml on its own (-c), then each deploy.<destination>.yml both merged
  # into deploy.yml (-d) and on its own (-c); repos use either.
  def configs
    @configs ||= begin
      base = File.join(path, "config/deploy.yml")
      destinations = Dir.glob(File.join(path, "config/deploy.*.yml")).sort
      list = []
      list << Config.new(self, kamal_mode: "config_file", config_file: "config/deploy.yml", files: [ base ]) if File.exist?(base)
      destinations.each do |file|
        name = File.basename(file, ".yml").delete_prefix("deploy.")
        list << Config.new(self, kamal_mode: "destination", destination: name, files: [ base, file ]) if File.exist?(base)
        list << Config.new(self, kamal_mode: "config_file", config_file: "config/#{File.basename(file)}", files: [ file ])
      end
      list
    end
  end

  def config(id)
    configs.find { |config| config.id == id } or raise NotFound, "No Kamal config #{id.inspect} in #{key}"
  end

  def kamal_binary
    File.executable?(File.join(path, "bin/kamal")) ? "bundled" : "global"
  end

  # What one way of running Kamal in this repo would deploy.
  class Config
    ERB_VALUE = "__erb__".freeze
    ENV_NAME = /ENV(?:\.fetch\(\s*|\[\s*)["']([A-Z][A-Z0-9_]*)["']/
    SECRET = /\A(?:#{SecretScrubber::SECRET_NAME}|#{SecretScrubber::ENV_KEY_NAME})\z/

    attr_reader :repo, :kamal_mode, :config_file, :destination, :error

    def initialize(repo, kamal_mode:, files:, config_file: nil, destination: nil)
      @repo = repo
      @kamal_mode = kamal_mode
      @config_file = config_file
      @destination = destination
      @files = files
      read
    end

    # How Add app's form names this choice: "config/deploy.yml" or "-d nbg".
    def id = destination ? "-d #{destination}" : config_file

    def kamal_binary = repo.kamal_binary
    def service = @data["service"]
    def hosts = @hosts ||= web_hosts.reject { it == ERB_VALUE }
    def hosts_from_erb? = web_hosts.include?(ERB_VALUE)
    def health_path = @data.dig("proxy", "healthcheck", "path") || "/up"
    def rails_default? = hosts.include?(RAILS_DEFAULT_HOST)

    # Kamal routes by hosts when it's set, else host. Real domains come first:
    # the health check uses the first one.
    def domains
      proxy = @data["proxy"] || {}
      Array(proxy["hosts"] || proxy["host"].to_s.split(",")).map { it.to_s.strip }
        .reject { it.blank? || it == ERB_VALUE }.partition { !it.end_with?(".sslip.io") }.flatten
    end

    # true or false as written; nil when the ERB decides.
    def ssl
      value = @data.dig("proxy", "ssl")
      value.nil? ? false : ([ true, false ].include?(value) ? value : nil)
    end

    # The plain settings the ERB reads from ENV, in order; secret names stay in .env.
    def env_names
      @files.flat_map { File.read(it).scan(ENV_NAME).flatten }.uniq.grep_v(SECRET)
    end

    private

    def read
      @data = @files.map { parse(File.read(it)) }.reduce({}) { |merged, data| merged.deep_merge(data) }
      @error = overlay_error
    rescue Psych::Exception => error
      @data = {}
      @error = "#{File.basename(@files.last)} isn't valid YAML: #{error.message}"
    end

    # A deploy.<destination>.yml read alone that only makes sense merged (-d).
    def overlay_error
      return if service.present? || destination || config_file == "config/deploy.yml"
      return unless File.exist?(File.join(repo.path, "config/deploy.yml"))

      "#{config_file} has no service, so it only adds to config/deploy.yml (use -d #{File.basename(config_file, ".yml").delete_prefix("deploy.")})"
    end

    # The YAML with each <% %> block dropped and each <%= %> replaced by a marker.
    def parse(text)
      yaml = text.gsub(/<%(?!=)(.*?)-?%>\n?/m, "").gsub(/<%=(.*?)-?%>/m, ERB_VALUE)
      YAML.safe_load(yaml, aliases: true) || {}
    end

    def web_hosts
      servers = @data["servers"]
      roles = servers.is_a?(Hash) ? (servers["web"] ? [ servers["web"] ] : servers.values) : [ servers ]
      roles.flat_map { |role| role.is_a?(Hash) ? Array(role["hosts"]) : Array(role) }
        .map { |host| host.is_a?(Hash) ? host.keys.first : host }.map(&:to_s)
    end
  end
end
