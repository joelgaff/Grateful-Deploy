# A throwaway repo whose bin/kamal is a shell script, so tests exercise the real
# Open3 path without touching Kamal or a server.
module FakeKamalRepo
  def build_fake_kamal_repo(script)
    repo = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(repo, "bin"))
    File.write(File.join(repo, "bin/kamal"), "#!/bin/sh\n#{script}")
    File.chmod(0o755, File.join(repo, "bin/kamal"))
    (@fake_kamal_repos ||= []) << repo
    repo
  end

  def remove_fake_kamal_repos
    Array(@fake_kamal_repos).each { |repo| FileUtils.rm_rf(repo) }
  end
end
