require "test_helper"
require "socket"

class HealthCheckTest < ActiveSupport::TestCase
  setup do
    @tcp = TCPServer.new("127.0.0.1", 0)
    @requests = Queue.new
    @server = servers(:nbg)
    @server.assign_attributes(host: "127.0.0.1", proxy_http_port: @tcp.addr[1])
    @app = apps(:storefront)
    @app.server = @server
  end

  teardown { @tcp.close }

  def respond_with(status_line)
    Thread.new do
      client = @tcp.accept
      request = +""
      request << client.gets until request.end_with?("\r\n\r\n")
      @requests << request
      client.write("HTTP/1.1 #{status_line}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      client.close
    end
  end

  test "gets the health path through kamal-proxy with the app's first domain as Host" do
    respond_with "200 OK"

    result = HealthCheck.new(@app).call

    assert result.healthy?
    assert_equal 200, result.code
    assert_kind_of Integer, result.response_ms
    request = @requests.pop
    assert request.start_with?("GET /up HTTP/1.1")
    assert_match(/^Host: storefront\.example\.com\r$/i, request)
  end

  test "a non-2xx response is unhealthy" do
    respond_with "502 Bad Gateway"

    result = HealthCheck.new(@app).call

    assert_not result.healthy?
    assert_equal 502, result.code
  end

  test "a connection failure is unhealthy with an error" do
    @tcp.close
    result = HealthCheck.new(@app).call

    assert_not result.healthy?
    assert_nil result.code
    assert_match(/refused/i, result.error)
  end
end
