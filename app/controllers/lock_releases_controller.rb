# Releases Kamal's deploy lock for an app (`kamal lock release`), queued like
# a deploy: it waits its turn, its output is kept, and status is checked after.
class LockReleasesController < ApplicationController
  include AppDeploying

  def create
    queue_deploy(kind: "release_lock")
  end
end
