require "test_helper"

# Deploys, live log follows and the status refresh are all long-running jobs.
class JobCapacityTest < ActiveSupport::TestCase
  def workers(env)
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/queue.yml")).deep_symbolize_keys.fetch(env).fetch(:workers)
  end

  def worker_threads(env)
    workers(env).sum { it.fetch(:threads) }
  end

  def pool_size(env, name)
    ActiveRecord::Base.configurations.configs_for(env_name: env, name: name).configuration_hash.fetch(:max_connections).to_i
  end

  test "development runs 6 jobs at once" do
    assert_equal 6, worker_threads(:development)
  end

  test "deploys have 3 slots of their own, so live logs can't hold them up" do
    deploy_workers = workers(:development).select { Array(it[:queues]) == [ "deploys" ] }

    assert_equal 3, deploy_workers.sum { it.fetch(:threads) }
  end

  test "each worker thread gets a connection to every database it uses, plus room for Solid Queue itself" do
    threads = worker_threads(:development)

    %w[primary queue cable].each do |name|
      assert_operator pool_size("development", name), :>=, threads + 2, "#{name} pool too small"
    end
  end
end
