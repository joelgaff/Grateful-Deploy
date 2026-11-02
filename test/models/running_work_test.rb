require "test_helper"

class RunningWorkTest < ActiveSupport::TestCase
  test "nothing running" do
    assert_nil RunningWork.describe
  end

  test "names the deploys and log sessions a restart would cut off" do
    apps(:storefront).deploys.create!(kind: "deploy")
    apps(:incidents).deploys.create!(kind: "deploy").tap(&:start!)
    apps(:storefront).log_sessions.create!(mode: "follow")

    assert_equal "2 deploys (incidents, storefront) and 1 log session (storefront) are running", RunningWork.describe
  end

  test "one deploy alone" do
    apps(:storefront).deploys.create!(kind: "deploy")

    assert_equal "1 deploy (storefront) is running", RunningWork.describe
  end
end
