ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "turbo/broadcastable/test_helper"
require_relative "test_helpers/failing_broadcasts"
require_relative "test_helpers/fake_command"
require_relative "test_helpers/fake_kamal_repo"
require_relative "test_helpers/git_repo"
# A hook run (pre-push from a worktree) or an exporting shell hands git variables to every process;
# the app code under test would then read and write the real repository instead of the fixtures.
GitRepo::GIT_LOCATION_VARIABLES.each { |name| ENV.delete(name) }
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # turbo-rails adds this only once ActionCable has loaded, so a test file
    # could get it or not depending on load order.
    include Turbo::Broadcastable::TestHelper
    include FailingBroadcasts
    include FakeCommand
    include FakeKamalRepo
    include GitRepo
    teardown { remove_fake_kamal_repos }
  end
end
