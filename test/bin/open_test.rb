require "test_helper"
require "open3"

# bin/open is what the Grateful Deploy launcher runs. Stand-ins for curl,
# systemctl, the Omarchy launcher and notify-send record what it does; curl
# "answers" once the fake service has been started.
class OpenTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @bin = File.join(@dir, "bin").tap { Dir.mkdir(it) }
    @log = File.join(@dir, "calls.log")
    fake "curl", %([ -f "$STATE/up" ])
    fake "systemctl", %q{echo "systemctl $*" >> "$LOG"; case "$*" in *" start "*) [ -n "$NEVER_UP" ] || touch "$STATE/up";; esac}
    fake "omarchy-launch-or-focus-webapp", %(echo "open $*" >> "$LOG")
    fake "notify-send", %(echo "notify $*" >> "$LOG")
    fake "sleep", "true"
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "with the service already answering, it just opens (or focuses) the window" do
    FileUtils.touch(File.join(@dir, "up"))

    assert run_open.success?

    assert_equal [ "open chrome-127.0.0.1__ http://127.0.0.1:3100" ], calls
  end

  test "with the service down, it starts it, waits for it to answer, then opens the window" do
    assert run_open.success?

    assert_equal "systemctl --user reset-failed grateful-deploy.service", calls[0]
    assert_equal "systemctl --user start grateful-deploy.service", calls[1]
    assert_match(/\Anotify .*Starting Grateful Deploy/, calls[2])
    assert_equal "open chrome-127.0.0.1__ http://127.0.0.1:3100", calls.last
  end

  test "if it never answers, it says so and opens nothing broken" do
    assert_not run_open("NEVER_UP" => "1").success?

    assert calls.none? { it.start_with?("open ") }
    assert_match(/\Anotify .*Grateful Deploy didn't start.*journalctl --user -u grateful-deploy/, calls.last)
  end

  private

  def fake(name, script)
    File.write(File.join(@bin, name), "#!/bin/sh\n#{script}\n")
    File.chmod(0o755, File.join(@bin, name))
  end

  def run_open(env = {})
    env = { "PATH" => "#{@bin}:#{ENV["PATH"]}", "STATE" => @dir, "LOG" => @log }.merge(env)
    _out, status = Open3.capture2e(env, Rails.root.join("bin/open").to_s)
    status
  end

  def calls = File.exist?(@log) ? File.readlines(@log, chomp: true) : []
end
