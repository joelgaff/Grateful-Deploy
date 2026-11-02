# The shared secret that Kamal's post-deploy hook in each app repo sends when
# it reports a deploy made outside Grateful Deploy (a terminal or CI). It lives
# in a file only this user can read (bin/release creates it); repos never
# contain it, so a web page can't fake deploys through the browser.
module HookToken
  mattr_accessor :path, default: ENV.fetch("GRATEFUL_DEPLOY_HOOK_TOKEN_FILE", File.expand_path("~/.config/grateful-deploy/hook_token"))

  def self.matches?(given)
    expected = File.read(path).strip
    expected.present? && given.present? && ActiveSupport::SecurityUtils.secure_compare(expected, given)
  rescue SystemCallError
    false
  end
end
