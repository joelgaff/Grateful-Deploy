# Add app, step one: every Kamal config in the repos under the repos folder,
# the ready ones first, each other one with the reason it can't be added.
class ReposController < ApplicationController
  def index
    @root = Rails.configuration.x.repos_root
    proposals = KamalRepo.scan(@root).flat_map(&:configs).map { AppProposal.new(Current.organization, it) }
    @ready, @blocked = proposals.partition(&:ready?)
  end
end
