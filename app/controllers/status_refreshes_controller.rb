class StatusRefreshesController < ApplicationController
  def create
    RefreshStatusJob.perform_later(force: true)
    redirect_back_or_to root_path, notice: "Checking now. The page updates as results arrive."
  end
end
