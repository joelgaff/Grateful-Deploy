require "test_helper"
require "socket"
require "openssl"

# HTTPS-only apps (Kamal proxy ssl: true) are checked over TLS: connect to the
# server's IP on its HTTPS port, name the domain for TLS, verify the certificate.
class HealthCheckHttpsTest < ActiveSupport::TestCase
  DOMAIN = "home.example.test".freeze

  setup do
    @key = OpenSSL::PKey::RSA.new(2048)
    @cert = self_signed_cert(DOMAIN, @key)
    @tcp = TCPServer.new("127.0.0.1", 0)
    @requests = Queue.new

    @server = servers(:nbg)
    @server.assign_attributes(host: "127.0.0.1", proxy_https_port: @tcp.addr[1])
    @app = apps(:storefront)
    @app.assign_attributes(server: @server, health_https: true, domains: [ DOMAIN ])

    @store = OpenSSL::X509::Store.new.tap { it.add_cert(@cert) }
  end

  teardown { @tcp.close unless @tcp.closed? }

  def respond_over_tls(status_line)
    sni = nil
    context = OpenSSL::SSL::SSLContext.new.tap { it.cert = @cert; it.key = @key }
    context.servername_cb = ->((_socket, name)) { sni = name; nil }
    Thread.new do
      ssl = OpenSSL::SSL::SSLSocket.new(@tcp.accept, context).tap(&:accept)
      @requests << [ sni, (+"").tap { |request| request << ssl.gets until request.end_with?("\r\n\r\n") } ]
      ssl.write("HTTP/1.1 #{status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      ssl.close
    rescue OpenSSL::SSL::SSLError, IOError
      @requests << :refused_tls
    end
  end

  test "gets the health path over TLS from the server's IP, naming the domain, with the certificate verified" do
    respond_over_tls "200 OK"

    result = HealthCheck.new(@app, cert_store: @store).call

    assert result.healthy?, result.error
    sni, request = @requests.pop
    assert_equal DOMAIN, sni
    assert request.start_with?("GET /up HTTP/1.1")
    assert_match(/^Host: #{Regexp.escape(DOMAIN)}\r$/i, request)
  end

  test "an untrusted certificate is unhealthy" do
    respond_over_tls "200 OK"

    result = HealthCheck.new(@app, cert_store: OpenSSL::X509::Store.new).call

    assert_not result.healthy?
    assert_match(/certificate verify failed/i, result.error)
  end

  test "with no domain yet there is nothing to check, and no request is made" do
    @app.domains = []

    result = HealthCheck.new(@app, cert_store: @store).call

    assert_not result.healthy?
    assert_nil result.code
    assert_equal "No domain to check yet", result.error
    assert @requests.empty?
  end

  private

  def self_signed_cert(name, key)
    OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{name}")
      cert.public_key = key.public_key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 3600
      extensions = OpenSSL::X509::ExtensionFactory.new.tap { it.subject_certificate = it.issuer_certificate = cert }
      cert.add_extension(extensions.create_extension("subjectAltName", "DNS:#{name}"))
      cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
      cert.sign(key, OpenSSL::Digest::SHA256.new)
    end
  end
end
