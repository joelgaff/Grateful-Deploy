require "test_helper"

class AppTest < ActiveSupport::TestCase
  def build_app(**attrs)
    servers(:nbg).apps.new({ name: "notes", repo_path: "/home/joel/Work/notes", service: "notes",
                             kamal_mode: "destination", destination: "nbg" }.merge(attrs))
  end

  test "valid with defaults for binary, health path, domains and active" do
    app = build_app

    assert app.valid?, app.errors.full_messages.to_sentence
    assert app.bundled?
    assert_equal "/up", app.health_path
    assert_equal [], app.domains
    assert app.active?
  end

  test "kamal env holds plain upper-case names with text values, or none yet" do
    assert build_app(kamal_env: { "BLOG_SERVER" => "203.0.113.30", "BLOG_DOMAIN" => nil }).valid?

    [ { "lower" => "x" }, { "BAD NAME" => "x" }, { "PORT" => 3000 }, { "LIST" => [ "a" ] } ].each do |env|
      app = build_app(kamal_env: env)
      assert_not app.valid?, env.inspect
      assert_includes app.errors[:kamal_env], "must map UPPER_CASE names to text"
    end
  end

  test "kamal env refuses secrets: they belong in the repo's .env, not fleet.yml" do
    %w[RAILS_MASTER_KEY KAMAL_REGISTRY_PASSWORD TELEGRAM_BOT_TOKEN STRIPE_KEY].each do |name|
      app = build_app(kamal_env: { name => "x" })
      assert_not app.valid?, name
      assert_includes app.errors[:kamal_env], "can't hold secrets (#{name}); keep them in the repo's .env"
    end
  end

  test "valid with no kamal env" do
    assert_equal({}, build_app.kamal_env)
  end

  test "requires name, service and repo path" do
    app = build_app(name: nil, service: nil, repo_path: nil)

    assert_not app.valid?
    %i[name service repo_path].each { |attr| assert_includes app.errors[attr], "can't be blank" }
  end

  test "repo path must be absolute" do
    app = build_app(repo_path: "Work/notes")

    assert_not app.valid?
    assert_includes app.errors[:repo_path], "must be an absolute path"
  end

  test "names are unique on a server" do
    assert_not build_app(name: apps(:storefront).name).valid?
  end

  test "destination mode needs a destination" do
    assert_not build_app(destination: nil).valid?
  end

  test "config file mode needs a config file" do
    app = build_app(kamal_mode: "config_file", destination: nil)

    assert_not app.valid?
    assert_includes app.errors[:config_file], "can't be blank"
  end

  test "fixtures round-trip domains as a list" do
    assert_equal [ "storefront.example.com" ], apps(:storefront).domains
    assert apps(:incidents).config_file_mode?
  end

  test "fixture apps never point at a real repo, so tests can't run git or gh against your work" do
    App.find_each { |app| assert_not File.exist?(app.repo_path), "#{app.name} fixture uses #{app.repo_path}" }
  end
end
