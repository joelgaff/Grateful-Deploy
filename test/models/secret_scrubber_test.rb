require "test_helper"

class SecretScrubberTest < ActiveSupport::TestCase
  def scrub(line) = SecretScrubber.scrub(line)

  test "masks values of known secret env names" do
    assert_equal "-e RAILS_MASTER_KEY=[FILTERED]", scrub("-e RAILS_MASTER_KEY=0123abcd")
    assert_equal "KAMAL_REGISTRY_PASSWORD: [FILTERED]", scrub("KAMAL_REGISTRY_PASSWORD: hunter2")
  end

  test "masks any env name that looks secret" do
    assert_equal "GEMINI_API_KEY=[FILTERED] MAILERSEND_SMTP_PASSWORD=[FILTERED]",
                 scrub("GEMINI_API_KEY=abc MAILERSEND_SMTP_PASSWORD=xyz")
    assert_equal "SECRET_KEY_BASE=\"[FILTERED]\"", scrub("SECRET_KEY_BASE=\"deadbeef\"")
  end

  test "masks long hex and base64-looking tokens" do
    assert_equal "token [FILTERED] end", scrub("token #{"a1" * 16} end")
    assert_equal "auth [FILTERED]", scrub("auth #{"Zm9vYmFy" * 5}==")
  end

  test "leaves ordinary output and short git shas alone" do
    line = "  INFO [3f2a1b9c] Running docker ps on 203.0.113.30"
    assert_equal line, scrub(line)
    assert_equal "Rolling back to 7d1e0f2a9c", scrub("Rolling back to 7d1e0f2a9c")
  end

  test "keeps full 40-char git shas visible since deploy versions are shas" do
    sha = "a" * 40
    assert_equal "image storefront:#{sha}", scrub("image storefront:#{sha}")
  end

  test "keeps docker sha256 digests visible since they are public image ids" do
    digest = "sha256:#{"0f" * 32}"
    assert_equal "FROM ruby:3.4.5-slim@#{digest} done", scrub("FROM ruby:3.4.5-slim@#{digest} done")
    assert_equal "token [FILTERED]", scrub("token #{"0f" * 32}")
  end
end
