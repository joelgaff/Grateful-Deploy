class ServersController < ApplicationController
  def index
    @servers = Current.organization.servers.order(:name).includes(:apps, :latest_server_snapshot)
  end

  def new
    @server = Current.organization.servers.new
  end

  def create
    @server = Current.organization.servers.new(params.expect(server: %i[name host ssh_user region proxy_http_port proxy_https_port notes]))
    if @server.save
      RefreshStatusJob.perform_later(force: true)
      redirect_to servers_path, **write_fleet_file
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # The server is added either way; fleet.yml is the record of it.
  def write_fleet_file
    FleetFile.new(Rails.configuration.x.fleet_file).add_server(@server)
    { notice: "Added #{@server.name}. Its entry is in config/fleet.yml: review it." }
  rescue FleetFile::Error, SystemCallError => error
    { alert: "Added #{@server.name}, but couldn't write config/fleet.yml (#{error.message}). Add its entry there by hand." }
  end
end
