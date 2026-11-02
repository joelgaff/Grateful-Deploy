class RollbacksController < ApplicationController
  include AppDeploying

  # Only versions the app has offered are accepted, never an arbitrary sha.
  def create
    version = @app.rollback_versions.find { |offered| offered == params[:version] }

    if version
      queue_deploy(kind: "rollback", version: version)
    else
      redirect_to @app, alert: "That version isn't one #{@app.name} can roll back to."
    end
  end
end
