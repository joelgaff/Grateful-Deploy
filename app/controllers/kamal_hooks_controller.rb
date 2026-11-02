# Kamal's post-deploy hook in an app repo reports a deploy made outside
# Grateful Deploy (a terminal, CI) here, so history and the rollback list stay
# complete. The hook isn't a browser: it sends HookToken instead of a session,
# which is also what stops a web page from faking deploys through the browser.
class KamalHooksController < ApplicationController
  skip_before_action :require_login
  skip_forgery_protection
  before_action :require_hook_token

  def post_deploy
    app = Current.organization.apps.find_by(service: params[:service], destination: params[:destination].presence)
    return head :not_found unless app

    deploy = app.record_outside_deploy!(command: params[:command], version: params[:version], runtime: params[:runtime])
    head(deploy ? :created : :ok)
  end

  private

  def require_hook_token
    head :unauthorized unless HookToken.matches?(request.authorization.to_s.delete_prefix("Bearer "))
  end
end
