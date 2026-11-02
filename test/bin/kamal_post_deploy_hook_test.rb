require "test_helper"
require "open3"

# config/kamal_hooks/post-deploy is the hook each app repo gets as
# .kamal/hooks/post-deploy. A stand-in curl records what it would send.
class KamalPostDeployHookTest < ActiveSupport::TestCase
  HOOK = Rails.root.join("config/kamal_hooks/post-deploy").to_s

  setup do
    @dir = Dir.mktmpdir
    @bin = File.join(@dir, "bin").tap { Dir.mkdir(it) }
    @token = File.join(@dir, "hook_token")
    File.write(File.join(@bin, "curl"), %(#!/bin/sh\necho "$@" > "$DIR/args"\ncat > "$DIR/stdin"\nexit ${CURL_EXIT:-0}\n))
    File.chmod(0o755, File.join(@bin, "curl"))
  end

  teardown { FileUtils.rm_rf(@dir) }

  def run_hook(env = {})
    env = { "PATH" => "#{@bin}:#{ENV["PATH"]}", "DIR" => @dir, "GRATEFUL_DEPLOY_HOOK_TOKEN_FILE" => @token,
            "KAMAL_SERVICE" => "storefront", "KAMAL_DESTINATION" => "nbg", "KAMAL_VERSION" => "3f82b48",
            "KAMAL_COMMAND" => "deploy", "KAMAL_RUNTIME" => "41" }.merge(env)
    Open3.capture3(env, HOOK)
  end

  test "posts the deploy to Grateful Deploy, with the token on stdin so it's not in the process list" do
    File.write(@token, "hook-secret\n")

    _out, _err, status = run_hook

    assert status.success?
    args = File.read(File.join(@dir, "args"))
    assert_includes args, "http://127.0.0.1:3100/kamal_hooks/post_deploy"
    %w[service=storefront destination=nbg version=3f82b48 command=deploy runtime=41].each { assert_includes args, it }
    assert_not_includes args, "hook-secret"
    assert_equal "Authorization: Bearer hook-secret\n", File.read(File.join(@dir, "stdin"))
  end

  test "on a machine without Grateful Deploy's token, does nothing" do
    _out, _err, status = run_hook

    assert status.success?
    assert_not File.exist?(File.join(@dir, "args"))
  end

  test "never fails the deploy, even when Grateful Deploy isn't running" do
    File.write(@token, "hook-secret\n")

    _out, err, status = run_hook("CURL_EXIT" => "7")

    assert status.success?
    assert_includes err, "Grateful Deploy didn't record this deploy"
  end
end
