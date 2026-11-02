# The Check CI button: asks GitHub whether local CI passed HEAD, then redraws
# the deploy controls.
class CiChecksController < ApplicationController
  def create
    @app = Current.organization.apps.find(params[:app_id])

    render turbo_stream: turbo_stream.replace(helpers.dom_id(@app, :deploy_controls),
                                              partial: "apps/deploy_controls", locals: { app: @app, fresh_ci: true })
  end
end
