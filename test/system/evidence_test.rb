require "application_system_test_case"

# bin/ci starts with bin/setup, which clears tmp/, so a flaky failure's
# screenshot must live somewhere that survives the next run.
class EvidenceTest < ApplicationSystemTestCase
  test "failure screenshots are kept in log/screenshots, which bin/setup doesn't clear" do
    assert_equal Rails.root.join("log/screenshots").to_s, Capybara.save_path.to_s
  end

  test "bin/ci keeps the browser tests' output and still fails when they fail" do
    assert_includes Rails.root.join("config/ci.rb").read,
                    %(step "Tests: Browser", "bash -o pipefail -c 'bin/rails test:system 2>&1 | tee log/browser-last.log'")
  end
end
