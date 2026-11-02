# Stops an app's running container (`kamal app stop`) to free its memory,
# queued like a deploy. Its data stays in its volume; Start or a deploy brings it back.
class StopsController < ApplicationController
  include AppDeploying

  def create
    if @app.running?
      queue_deploy(kind: "stop")
    else
      redirect_to @app, alert: "#{@app.name} isn't running."
    end
  end
end
