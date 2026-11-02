require "test_helper"

class ProcessGroupTest < ActiveSupport::TestCase
  def spawn_group(script)
    Process.spawn("sh", "-c", script, pgroup: true)
  end

  def assert_group_gone(pid)
    Timeout.timeout(5) { sleep 0.05 while ProcessGroup.alive?(pid) }
    assert_not ProcessGroup.alive?(pid)
  end

  test "terminate ends a group that stops on TERM" do
    pid = spawn_group("sleep 30 & wait")

    ProcessGroup.terminate(pid, grace: 2)

    Timeout.timeout(5) { Process.wait(pid) }
    assert_group_gone(pid)
  end

  test "terminate kills a group that ignores TERM once the grace period ends" do
    pid = spawn_group("trap '' TERM; sleep 30 & wait")
    sleep 0.2 # let the trap install

    ProcessGroup.terminate(pid, grace: 0.5)

    Timeout.timeout(5) { Process.wait(pid) }
    assert_group_gone(pid)
  end

  test "terminate ignores a group that is already gone" do
    assert_nothing_raised { ProcessGroup.terminate(999_999_999, grace: 0.1) }
  end
end
