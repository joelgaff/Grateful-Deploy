class DeploysController < ApplicationController
  include AppDeploying

  def show
    @deploy = @app.deploys.find(params[:id])
  end

  def create
    queue_deploy
  end
end
