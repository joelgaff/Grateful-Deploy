# Writes an app or server added in Grateful Deploy into config/fleet.yml (an app
# after its server's last app, a server after the last server) as plain text so
# the file's comments and layout stay put. Only the settings that differ from
# the defaults are written.
class FleetFile
  class Error < StandardError; end

  def initialize(path)
    @path = path.to_s
  end

  def add(app, server_name:)
    lines = File.readlines(@path)
    data = YAML.load(lines.join) || {}
    raise Error, "config/fleet.yml has no server #{server_name}" unless data.dig("servers", server_name)
    raise Error, "config/fleet.yml already lists #{app.name} under #{server_name}" if data.dig("servers", server_name, "apps")&.key?(app.name)

    File.write(@path, insert(lines, server_name, entry(app, with_apps_key: !data.dig("servers", server_name).key?("apps"))).join)
  end

  def add_server(server)
    lines = File.readlines(@path)
    data = YAML.load(lines.join) || {}
    raise Error, "config/fleet.yml already lists server #{server.name}" if data["servers"]&.key?(server.name)

    File.write(@path, append_server(lines, server_entry(server)).join)
  end

  private

  # After the servers list's last line that isn't blank: it runs until the next
  # top-level key.
  def append_server(lines, entry)
    start = lines.index { it.match?(/\Aservers:\s*\z/) } or raise Error, "config/fleet.yml has no servers list"
    finish = (start + 1...lines.size).find { |index| lines[index].match?(/\A[^\s#]/) } || lines.size
    finish -= 1 while finish > start + 1 && lines[finish - 1].strip.empty?
    lines[finish - 1] = "#{lines[finish - 1].chomp}\n"
    lines.insert(finish, *([ "\n" ] if finish > start + 1), *entry)
  end

  def server_entry(server)
    defaults = Server.new
    settings = {
      host: scalar(server.host),
      ssh_user: (scalar(server.ssh_user) unless server.ssh_user == defaults.ssh_user),
      region: (scalar(server.region) if server.region.present?),
      proxy_http_port: (server.proxy_http_port unless server.proxy_http_port == defaults.proxy_http_port),
      proxy_https_port: (server.proxy_https_port unless server.proxy_https_port == defaults.proxy_https_port),
      notes: (scalar(server.notes) if server.notes.present?)
    }.compact
    [ "  #{server.name}:\n", *settings.map { |name, value| "    #{name}: #{value}\n" } ]
  end

  # After the server's last line that isn't blank: its section runs until the
  # next line indented two spaces or less.
  def insert(lines, server_name, entry)
    start = lines.index { it.match?(/\A  #{Regexp.escape(server_name)}:\s*\z/) }
    finish = (start + 1...lines.size).find { |index| lines[index].match?(/\A {0,2}\S/) } || lines.size
    finish -= 1 while finish > start + 1 && lines[finish - 1].strip.empty?
    lines[finish - 1] = "#{lines[finish - 1].chomp}\n"
    lines.insert(finish, *entry)
  end

  def entry(app, with_apps_key:)
    lines = []
    lines << "    apps:\n" if with_apps_key
    lines << "      #{app.name}:\n"
    settings(app).each do |name, value|
      if value.is_a?(Hash)
        lines << "        #{name}:\n"
        value.each { |key, text| lines << "          #{key}: #{scalar(text)}\n" }
      else
        lines << "        #{name}: #{value}\n"
      end
    end
    lines
  end

  def settings(app)
    {
      repo_path: scalar(app.repo_path.sub(/\A#{Regexp.escape(Dir.home)}(?=\/)/, "~")),
      destination: (scalar(app.destination) if app.destination_mode?),
      config_file: (scalar(app.config_file) if app.config_file_mode?),
      kamal_binary: ("global" if app.global?),
      service: scalar(app.service),
      health_path: (scalar(app.health_path) unless app.health_path == "/up"),
      health_https: ("true" if app.health_https?),
      kamal_env: app.kamal_env.presence,
      domains: "[#{app.domains.map { scalar(it) }.join(", ")}]"
    }.compact
  end

  # A YAML scalar, quoted only when YAML would read it as something else.
  def scalar(value)
    plain = value.to_s.match?(%r{\A[\w.~/@-][\w.~/@:-]*\z}) && YAML.safe_load(value.to_s) == value
    plain ? value : Psych.dump(value).delete_prefix("--- ").chomp
  end
end
