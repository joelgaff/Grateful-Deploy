# Clean up after a crash or restart, once Solid Queue's worker boots (inside
# Puma via bin/dev). Not on app boot, so a console or runner never touches
# a deploy that is genuinely running.
#
# This must run in the worker, not the supervisor (SolidQueue.on_start): the
# cleanup broadcasts, which starts Solid Cable's writer thread, and a writer
# started in the supervisor is dead in the forked worker. Every later broadcast
# from jobs would then be silently dropped.
Rails.application.config.after_initialize do
  SolidQueue.on_worker_start do
    Deploy.fail_abandoned!
    LogSession.stop_abandoned!
  end
end
