require "open3"

# Runs a short read-only command (git, gh) and returns its stdout, or nil if it
# fails or runs past `timeout`. A stuck command is killed with its whole
# process group, so it can't hang a page.
module QuickCommand
  def self.capture(env, *argv, timeout:, chdir: Dir.pwd)
    Open3.popen2(env, *argv, chdir: chdir, err: File::NULL, pgroup: true) do |stdin, stdout, wait|
      stdin.close
      output = Thread.new { stdout.read }
      ProcessGroup.signal("KILL", wait.pid) unless wait.join(timeout)
      text = output.value # killed or not, the pipe closes and the reader ends
      text if wait.value.success?
    end
  rescue SystemCallError
    nil
  end
end
