class LogSessionsController < ApplicationController
  before_action :set_app

  def create
    session = @app.log_sessions.create!(mode: params[:mode] == "follow" ? "follow" : "recent")
    LogSessionJob.perform_later(session)
    redirect_to app_path(@app, anchor: "logs")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to app_path(@app, anchor: "logs"), alert: "#{@app.name} is already showing logs"
  end

  # From the page, stay put so the lines already streamed stay readable;
  # the buttons switch back through the session's broadcast.
  def destroy
    @app.log_sessions.find(params[:id]).stop!

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to app_path(@app, anchor: "logs") }
    end
  end

  private

  def set_app
    @app = Current.organization.apps.find(params[:app_id])
  end
end
