# Starts a stopped app's container again (`kamal app start`), the version the
# last status check found stopped, never one from request params.
class StartsController < ApplicationController
  include AppDeploying

  def create
    if (version = @app.stopped_version)
      queue_deploy(kind: "start", version: version)
    else
      redirect_to @app, alert: "#{@app.name} isn't stopped."
    end
  end
end
