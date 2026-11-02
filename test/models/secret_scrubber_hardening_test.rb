require "test_helper"

# Real-world shapes of secrets in deploy output and app logs. Every secret
# value below must disappear; the surrounding text must stay readable.
class SecretScrubberHardeningTest < ActiveSupport::TestCase
  SECRET = "s3cr3tV4lue".freeze

  def assert_masked(line, secret = SECRET)
    scrubbed = SecretScrubber.scrub(line)
    assert_not_includes scrubbed, secret, "leaked in: #{scrubbed}"
    assert_includes scrubbed, SecretScrubber::FILTERED, "nothing masked in: #{scrubbed}"
  end

  test "secret-named keys in any case and assignment style" do
    [
      "password=#{SECRET}",
      "Password: #{SECRET}",
      "db_password = #{SECRET}",
      "export STRIPE_SECRET_KEY=#{SECRET}",
      "api_key=#{SECRET}",
      "apiKey: #{SECRET}",
      "access_key_id=#{SECRET}",
      "client_secret=#{SECRET}",
      "auth_token=#{SECRET}",
      "private_key: #{SECRET}",
      "otp_secret=#{SECRET}",
      "session_id=#{SECRET}",
      "signature=#{SECRET}"
    ].each { |line| assert_masked(line) }
  end

  test "quoted and structured values, including ones with spaces" do
    [
      %({"password":"#{SECRET} with spaces"}),
      %({"user":"joel","api_key": "#{SECRET}"}),
      %(Parameters: {"token"=>"#{SECRET}", "page"=>"2"}),
      %(:secret => "#{SECRET}"),
      %(password='#{SECRET}'),
      %(<input name="authenticity_token" value="#{SECRET}">)
    ].each { |line| assert_masked(line) }
  end

  test "query strings keep other params readable" do
    line = "GET /callback?access_token=#{SECRET}&page=2 HTTP/1.1"
    scrubbed = SecretScrubber.scrub(line)

    assert_not_includes scrubbed, SECRET
    assert_includes scrubbed, "&page=2 HTTP/1.1"
  end

  test "authorization, cookie and token headers" do
    [
      "Authorization: Bearer #{SECRET}",
      "authorization: Basic #{SECRET}",
      "Authorization: token #{SECRET}",
      "Cookie: _app_session=#{SECRET}; theme=dark",
      "Set-Cookie: _app_session=#{SECRET}; path=/; HttpOnly",
      "X-Api-Key: #{SECRET}",
      "X-Auth-Token: #{SECRET}",
      "curl -H 'Authorization: Bearer #{SECRET}' https://api.example.com"
    ].each { |line| assert_masked(line) }
  end

  test "passwords inside urls" do
    assert_equal "postgres://app:[FILTERED]@db.internal:5432/prod",
                 SecretScrubber.scrub("postgres://app:#{SECRET}@db.internal:5432/prod")
    assert_masked("git clone https://x-access-token:#{SECRET}@github.com/example/storefront.git")
    assert_masked("redis://:#{SECRET}@localhost:6379/0")
  end

  test "well-known token formats anywhere in a line" do
    {
      "github classic" => "ghp_#{"a1B2" * 9}",
      "github fine-grained" => "github_pat_11ABCDEFG0#{"x9Y8" * 10}",
      "stripe" => "sk_live_#{"Ab12" * 6}",
      "aws access key" => "AKIA#{"ABCD2345" * 2}",
      "google" => "AIza#{"Sy0-abcDEF_12345" * 2}xyz",
      "slack" => "xoxb-1234567890-0987654321-#{"aBcD" * 6}",
      "openai/anthropic" => "sk-ant-api03-#{"aB3-" * 10}",
      "gitlab" => "glpat-#{"aB3d" * 5}",
      "npm" => "npm_#{"aB3d" * 9}",
      "hugging face" => "hf_#{"aBcD" * 9}",
      "sendgrid" => "SG.#{"aB3d" * 6}.#{"xY9z" * 11}",
      "mailersend" => "mlsn.#{"0a1b" * 16}",
      "jwt" => "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.#{"dQw4w9WgXcQ" * 3}"
    }.each do |name, token|
      scrubbed = SecretScrubber.scrub("using #{token} now")
      assert_not_includes scrubbed, token, "#{name} leaked: #{scrubbed}"
      assert_equal "using [FILTERED] now", scrubbed, name
    end
  end

  test "private key blocks" do
    assert_masked("-----BEGIN OPENSSH PRIVATE KEY-----", "OPENSSH PRIVATE KEY-----")
    assert_masked("b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW",
                  "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW")
  end

  test "long single-case random strings" do
    assert_masked("token #{"k3j9x2m8" * 5}", "k3j9x2m8" * 5)          # lowercase + digits
    assert_masked("secret JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP", "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP") # base32
  end

  test "keeps ordinary deploy output readable" do
    [
      "  INFO [3f2a1b9c] Running docker ps on 203.0.113.30",
      "  INFO [67e2f399] Running docker run --detach --name storefront-web-nbg-f5956902a92a15920788c2d4e319966db0565461 --network kamal",
      "  INFO Running /usr/bin/env git -C /tmp/kamal-clones/storefront-3d4909e1ed208/storefront/ reset --hard f5956902a92a15920788c2d4e319966db0565461",
      "DEBUG #6 FROM docker.io/library/ruby:3.4.5-slim@sha256:#{"0f" * 32}",
      "Releasing the deploy lock...",
      "  Finished all in 37.6 seconds",
      %(2026-10-15T18:58:07Z {"level":"INFO","msg":"Request","path":"/up","status":200,"user_agent":"Ruby"}),
      "Started GET \"/races?page=2\" for 127.0.0.1",
      "Processing by SessionsController#create as TURBO_STREAM",
      "Completed 302 Found in 12ms (ActiveRecord: 1.1ms | Allocations: 3021)",
      "  INFO [5c1d] Running docker ps on root@203.0.113.30",
      "  INFO Uploading ruby@3.4.5 to user@localhost",
      "key_count=12 primary key lookup"
    ].each { |line| assert_equal line, SecretScrubber.scrub(line) }
  end

  test "email addresses, like Rails' filter_parameters; IPs stay visible" do
    assert_equal "Author: Joel <[FILTERED]>", SecretScrubber.scrub("Author: Joel <dev@example.com>")
    assert_equal "Sent login code to [FILTERED] from 203.0.113.9",
                 SecretScrubber.scrub("Sent login code to first.last+tag@mail.example.co.uk from 203.0.113.9")
    assert_equal %({"email":"[FILTERED]","ip":"203.0.113.9"}),
                 SecretScrubber.scrub(%({"email":"Someone@Example.COM","ip":"203.0.113.9"}))
    assert_equal %(Started GET "/sessions?email=[FILTERED]&page=2" for 203.0.113.9),
                 SecretScrubber.scrub(%(Started GET "/sessions?email=joel%40hey.com&page=2" for 203.0.113.9))
  end

  test "very long lines are checked quickly, whatever their shape" do
    [ "a" * 20_000 + "@", "a." * 10_000 + "@b", "a@" + "b" * 20_000, "password" * 2_500,
      "A" * 20_000, "\"" + "x" * 20_000, "#{"k" * 20_000}=\"v\"", %(name="secret" value=) * 4_000, "-eyJ" * 20_000, "eyJ" * 20_000 ].each do |line|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      SecretScrubber.scrub(line)
      # Generous for a busy machine; a quadratic pattern hits the 1 s regex timeout instead.
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.8, line.first(20)
    end
  end

  test "a line that still takes too long to check is hidden, never shown unchecked or raised" do
    limit = Regexp.timeout
    Regexp.timeout = 0.000001

    assert_equal "[line hidden: too long to check for secrets]", SecretScrubber.scrub("Bearer " * 20_000)
  ensure
    Regexp.timeout = limit
  end

  test "scrubbing is idempotent" do
    once = SecretScrubber.scrub("password=#{SECRET} Authorization: Bearer #{SECRET} to dev@example.com")

    assert_equal once, SecretScrubber.scrub(once)
  end
end
