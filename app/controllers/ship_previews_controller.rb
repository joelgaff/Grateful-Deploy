# What a deploy would ship right now, read fresh at the moment it's asked for:
# as text for the Deploy confirm (CI asked fresh too), or as the re-rendered
# deploy controls when the tab regains focus (CI answer reused).
class ShipPreviewsController < ApplicationController
  def show
    @app = Current.organization.apps.find(params[:app_id])
    respond_to do |format|
      format.text { render plain: helpers.deploy_confirm(@app, ShipPreview.new(@app, fresh_ci: true)) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@app, :deploy_controls),
                                                  partial: "apps/deploy_controls", locals: { app: @app })
      end
    end
  end
end
