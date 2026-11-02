require "test_helper"

# config/fleet.example.yml, and this machine's config/fleet.yml when it has one,
# so a mistake in either fails CI instead of the next seed.
class FleetFileTest < ActiveSupport::TestCase
  FLEETS = %w[config/fleet.example.yml config/fleet.yml].map { Rails.root.join(it) }.select(&:exist?)

  FLEETS.each do |path|
    name = path.basename

    test "every app in #{name} imports valid" do
      servers = import(path)

      assert servers.flat_map(&:apps).any?
      servers.flat_map(&:apps).each { |app| assert app.valid?, "#{app.name}: #{app.errors.full_messages.to_sentence}" }
    end

    # An app checked over HTTPS lists the domain to check first; an sslip.io
    # host there would only ever be a test address.
    test "every app in #{name} checked over HTTPS lists a real domain first" do
      import(path).flat_map(&:apps).select(&:health_https?).each do |app|
        assert app.domains.any?, "#{app.name} has no domain to check"
        assert_not app.domains.first.end_with?(".sslip.io"), "#{app.name} should list its real domain first"
      end
    end
  end

  test "the example imports both ways of choosing a Kamal config" do
    apps = import(Rails.root.join("config/fleet.example.yml")).flat_map(&:apps).index_by(&:name)

    assert_equal [ "-d", "production" ], apps.fetch("blog").kamal_target_args
    assert_equal [ "-c", "config/deploy.production.yml" ], apps.fetch("shop").kamal_target_args
    assert apps.fetch("shop").global?
  end

  private
    def import(path)
      Fleet.import(path, organization: organizations(:primary))
      organizations(:primary).servers.where(name: YAML.load_file(path)["servers"].keys).includes(:apps).to_a
    end
end
