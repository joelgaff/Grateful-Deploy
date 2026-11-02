class AppsController < ApplicationController
  # The repo and config come from the scan, never as a path from the form.
  before_action :set_proposal, only: %i[new create]

  def index
    @servers = Current.organization.servers.order(:name)
      .includes(apps: %i[latest_status_snapshot running_status_snapshot latest_deploy])
  end

  def show
    @app = Current.organization.apps.find(params[:id])
  end

  def new
    @app = @proposal.build(name: @proposal.defaults[:name])
  end

  def create
    @app = @proposal.build(**params.expect(app: [ :name, :server_id, :domains, :health_path, :health_https, kamal_env: {} ]).to_h.symbolize_keys)
    if @app.save
      RefreshStatusJob.perform_later(force: true)
      redirect_to @app, **write_fleet_file
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_proposal
    repo = KamalRepo.find(Rails.configuration.x.repos_root, params.require(:repo))
    @proposal = AppProposal.new(Current.organization, repo.config(params.require(:config)))
    redirect_to repos_path, alert: @proposal.blocked_reason unless @proposal.ready?
  rescue KamalRepo::NotFound
    head :not_found
  end

  # The app is added either way; fleet.yml is the record of it.
  def write_fleet_file
    FleetFile.new(Rails.configuration.x.fleet_file).add(@app, server_name: @app.server.name)
    { notice: "Added #{@app.name}. Its entry is in config/fleet.yml: review it." }
  rescue FleetFile::Error, SystemCallError => error
    { alert: "Added #{@app.name}, but couldn't write config/fleet.yml (#{error.message}). Add its entry there by hand." }
  end
end
