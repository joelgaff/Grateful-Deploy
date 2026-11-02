# Stops a process group started with pgroup: true (Kamal plus everything it
# spawned). TERM first, so Kamal's cleanup can run and release its deploy lock;
# KILL if anything is still alive after the grace period.
module ProcessGroup
  def self.terminate(pid, grace: 10)
    signal("TERM", pid)
    Thread.new do
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + grace
      sleep 0.1 while alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      signal("KILL", pid) if alive?(pid)
    end
  end

  def self.alive?(pid)
    Process.kill(0, -pid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  def self.signal(name, pid)
    Process.kill(name, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    # Already gone.
  end
end
