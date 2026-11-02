# Catch-up for an open deploy page: the saved lines after the last one it
# shows, for the lines streamed before its live connection was ready.
class DeployLinesController < ApplicationController
  def index
    @deploy = Current.organization.apps.find(params[:app_id]).deploys.find(params[:deploy_id])
    after = params[:after].to_s.match?(/\A\d+\z/) ? params[:after].to_i : 0
    @lines = @deploy.numbered_lines(after: after)
  end
end
