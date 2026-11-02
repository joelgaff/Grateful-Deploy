# The `kamal` installed for this user's Ruby, for apps set to kamal_binary:
# global. Its full path is looked up once from the home folder: inside a repo,
# mise puts the repo's own bin/ first on PATH, so a bare "kamal" there would
# run the repo's bin/kamal (and its bundled, maybe uninstalled, gems) instead.
module GlobalKamal
  class NotFound < StandardError; end

  mattr_accessor :resolver, default: ->(dir) { QuickCommand.capture({}, "mise", "which", "kamal", timeout: 10, chdir: dir) }

  def self.path
    @path ||= begin
      found = resolver.call(Dir.home).to_s.strip
      raise NotFound, "No global kamal found (mise which kamal, from #{Dir.home})" unless found.start_with?("/")
      found
    end
  end

  def self.reset
    @path = nil
  end
end
