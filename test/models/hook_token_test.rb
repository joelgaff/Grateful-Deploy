require "test_helper"

class HookTokenTest < ActiveSupport::TestCase
  setup do
    @path = HookToken.path
    @dir = Dir.mktmpdir
    HookToken.path = File.join(@dir, "hook_token")
  end

  teardown do
    HookToken.path = @path
    FileUtils.rm_rf(@dir)
  end

  test "the token lives in this user's config, outside every repo" do
    assert_equal File.expand_path("~/.config/grateful-deploy/hook_token"), @path
  end

  test "matches only the token in the file" do
    File.write(HookToken.path, "s3cret-token\n")

    assert HookToken.matches?("s3cret-token")
    assert_not HookToken.matches?("s3cret-tokenX")
    assert_not HookToken.matches?("")
    assert_not HookToken.matches?(nil)
  end

  test "with no token file, nothing matches (outside-deploy recording is off)" do
    assert_not HookToken.matches?("anything")
  end

  test "an empty file matches nothing, not an empty token" do
    File.write(HookToken.path, "\n")

    assert_not HookToken.matches?("")
  end
end
