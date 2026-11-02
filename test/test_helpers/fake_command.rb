# Puts a fake executable first on PATH for the block, so code that shells out
# to git or gh runs a script instead (no network, no real repo needed).
module FakeCommand
  def with_fake_command(name, script)
    bin = Dir.mktmpdir
    File.write(File.join(bin, name), "#!/bin/sh\n#{script}\n")
    File.chmod(0o755, File.join(bin, name))
    path = ENV["PATH"]
    ENV["PATH"] = "#{bin}:#{path}"
    yield
  ensure
    ENV["PATH"] = path
    FileUtils.rm_rf(bin)
  end
end
