namespace :grateful_deploy do
  desc "Re-mask saved deploy logs with the current SecretScrubber rules"
  task rescrub_logs: :environment do
    Deploy.rescrub_logs!
    puts "Re-masked #{Deploy.count} deploy logs."
  end

  desc "Exit non-zero if a deploy or log session is running (bin/release checks this before restarting)"
  task assert_idle: :environment do
    if (busy = RunningWork.describe)
      abort "Not restarting: #{busy}. Try again when they finish."
    end
  end
end
