require "open3"

# Read-only look at a server over SSH: containers, their memory, and which
# Kamal app version each one runs. Commands are fixed strings — nothing from
# a request ever reaches the remote shell.
class ServerProbe
  class Error < StandardError; end

  COMMANDS = {
    # -a: a stopped app's container too, so it shows as stopped, not missing.
    docker_ps: "docker ps -a --format '{{json .}}'",
    docker_stats: "docker stats --no-stream --format '{{json .}}'",
    free: "free -b",
    df: "df -B1 /",
    loadavg: "cat /proc/loadavg && nproc",
    # Kamal's deploy locks: a folder per locked app holding base64 details
    # (Kamal::Commands::Lock). Read-only; no locks is a normal, successful answer.
    kamal_locks: %(for d in .kamal/lock-*; do [ -d "$d" ] && echo "== ${d##*/}" && base64 -d "$d/details" && echo; done; true)
  }.freeze

  Container = Data.define(:name, :image, :service, :role, :state, :status, :memory_bytes) do
    def version = (image.split(":").last if image.include?(":"))
    def web? = role == "web"
    def running? = state == "running"
  end

  Memory = Data.define(:total, :used, :available, :swap_total, :swap_used)
  Disk = Data.define(:total, :used, :available)
  Load = Data.define(:one, :five, :fifteen, :cpus)

  def initialize(server, runner: SshRunner.new(server))
    @runner = runner
  end

  def containers
    @containers ||= begin
      memory = json_lines(:docker_stats).to_h { |stat| [ stat["Name"], parse_memory(stat["MemUsage"]) ] }
      json_lines(:docker_ps).map do |ps|
        labels = parse_labels(ps["Labels"])
        Container.new(name: ps["Names"], image: ps["Image"], service: labels["service"], role: labels["role"],
                      state: ps["State"], status: ps["Status"], memory_bytes: memory[ps["Names"]])
      end
    end
  end

  # Lock folder name ("lock-storefront-nbg") => what Kamal wrote (who, when,
  # version, message), masked like all other output.
  def kamal_locks
    @runner.call(:kamal_locks).split(/^== /).reject(&:blank?).to_h do |section|
      name, details = section.split("\n", 2)
      [ name.strip, details.to_s.strip.lines.map { SecretScrubber.scrub(it.chomp) }.join("\n") ]
    end
  end

  def memory
    rows = @runner.call(:free).lines.to_h { |line| [ line.split.first, line.split.drop(1).map(&:to_i) ] }
    mem, swap = rows.fetch("Mem:"), rows.fetch("Swap:")
    Memory.new(total: mem[0], used: mem[1], available: mem[5], swap_total: swap[0], swap_used: swap[1])
  end

  def disk
    _filesystem, total, used, available = @runner.call(:df).lines.last.split
    Disk.new(total: total.to_i, used: used.to_i, available: available.to_i)
  end

  def load
    averages, cpus = @runner.call(:loadavg).lines
    one, five, fifteen = averages.split.first(3).map(&:to_f)
    Load.new(one: one, five: five, fifteen: fifteen, cpus: cpus.to_i)
  end

  private

  def json_lines(command)
    @runner.call(command).lines.filter_map { |line| JSON.parse(line) if line.strip.start_with?("{") }
  end

  UNITS = { "B" => 1, "kB" => 1000, "KiB" => 1024, "MB" => 1000**2, "MiB" => 1024**2,
            "GB" => 1000**3, "GiB" => 1024**3 }.freeze

  # "a=1,b=2": a piece without "=" belongs to the value before it, since a
  # value can hold commas.
  def parse_labels(text)
    text.to_s.split(",").each_with_object({}) do |piece, labels|
      if piece.include?("=") || labels.empty?
        name, value = piece.split("=", 2)
        labels[name] = value
      else
        labels[labels.keys.last] = "#{labels.values.last},#{piece}"
      end
    end
  end

  def parse_memory(usage)
    amount, unit = usage.to_s.split("/").first.to_s.strip.match(/\A([\d.]+)\s*([A-Za-z]+)\z/)&.captures
    (amount.to_f * UNITS.fetch(unit)).round if amount && UNITS.key?(unit)
  end

  # Runs every command in COMMANDS over ONE ssh connection and hands each
  # caller its section. The server's ufw LIMITs port 22 (6 connections in
  # 30s), so one connection per command would lock us, and Kamal, out.
  class SshRunner
    def self.marker(key) = "@@grateful-deploy:#{key}@@"

    def self.raise_for(stderr)
      if stderr.include?("communication with agent failed")
        raise Error, "SSH agent refused. Unlock 1Password (SSH agent) and try again."
      elsif stderr.include?("Connection refused")
        raise Error, "SSH connection refused, probably the server's SSH rate limit (ufw). It clears in about 30 seconds."
      end
      raise Error, "SSH failed: #{stderr.strip.lines.last}"
    end

    def initialize(server, executor: Open3.method(:capture3))
      @server = server
      @executor = executor
    end

    def argv
      script = COMMANDS.map { |key, command| "echo '#{self.class.marker(key)}'; #{command}" }.join("; ")
      [ "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "#{@server.ssh_user}@#{@server.host}", script ]
    end

    def call(command)
      COMMANDS.fetch(command)
      sections.fetch(command, "")
    end

    private

    def sections
      @sections ||= begin
        output, errors, status = @executor.call(*argv)
        self.class.raise_for(errors) unless status.success?
        split(output)
      end
    end

    def split(output)
      markers = COMMANDS.keys.index_by { |key| self.class.marker(key) }
      current = nil
      output.each_line.with_object(Hash.new { |hash, key| hash[key] = +"" }) do |line, sections|
        if (key = markers[line.chomp])
          current = key
        elsif current
          sections[current] << line
        end
      end
    end
  end
end
