class DeployCancellationsController < ApplicationController
  def create
    app = Current.organization.apps.find(params[:app_id])
    deploy = app.deploys.find(params[:deploy_id])

    if deploy.cancel!
      redirect_to app_deploy_path(app, deploy), notice: "Canceled. Check the app before deploying again."
    else
      redirect_to app_deploy_path(app, deploy), alert: "This deploy already finished."
    end
  end
end
