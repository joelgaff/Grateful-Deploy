class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_organization

  private

  # SINGLE-TENANT today: the one tenant. (.sole raises if a 2nd appears — a useful guard.)
  # MULTI-TENANT later: resolve by subdomain/session, e.g.
  #   Organization.find_by!(subdomain: request.subdomain)
  def set_organization
    Current.organization = Organization.first
  end
end
