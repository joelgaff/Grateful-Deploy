require "net/http"

# Hits an app's health path through the server's kamal-proxy, routed by the
# app's first domain as the Host header (works before DNS points at the server).
# An HTTPS-only app (health_https) is checked over TLS on the proxy's HTTPS
# port: connected by the server's IP, the domain named for TLS, the
# certificate verified.
class HealthCheck
  Result = Data.define(:code, :response_ms, :error) do
    def healthy? = code.present? && (200..299).cover?(code)
  end

  NO_DOMAIN = "No domain to check yet".freeze

  # cert_store: the certificates to trust (tests); the system's by default.
  def initialize(app, cert_store: nil)
    @app = app
    @cert_store = cert_store
  end

  def call
    return Result.new(code: nil, response_ms: nil, error: NO_DOMAIN) if @app.health_https? && @app.domains.empty?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = connection.start { |http| http.get(@app.health_path, "Host" => @app.domains.first || @app.server.host) }
    Result.new(code: response.code.to_i, response_ms: elapsed_ms(started), error: nil)
  rescue StandardError => error
    Result.new(code: nil, response_ms: nil, error: "#{error.class}: #{error.message}")
  end

  private

  def connection
    server = @app.server
    http =
      if @app.health_https?
        Net::HTTP.new(@app.domains.first, server.proxy_https_port).tap do |https|
          https.ipaddr = server.host
          https.use_ssl = true
          https.verify_mode = OpenSSL::SSL::VERIFY_PEER
          https.cert_store = @cert_store if @cert_store
        end
      else
        Net::HTTP.new(server.host, server.proxy_http_port)
      end
    http.tap { it.open_timeout = 5; it.read_timeout = 10 }
  end

  def elapsed_ms(started)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end
end
