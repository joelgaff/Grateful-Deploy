# Shared by the controllers that queue a Deploy (deploy, rollback): the app is
# always found through Current.organization, and the in-flight lock becomes a
# friendly alert instead of an error page.
module AppDeploying
  extend ActiveSupport::Concern

  included do
    before_action :set_app
  end

  private

  def set_app
    @app = Current.organization.apps.find(params[:app_id])
  end

  def queue_deploy(**options)
    deploy = @app.start_deploy!(**options)
    redirect_to app_deploy_path(@app, deploy)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to @app, alert: error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    # Two clicks raced past the validation; the database index caught the second.
    redirect_to @app, alert: "#{@app.name} already has a deploy in progress"
  end
end
