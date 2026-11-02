require "test_helper"

# Add app: the dashboard links to the repos under the repos folder that have
# Kamal config; a ready config opens a form filled in from it; saving adds the
# app here and writes it into config/fleet.yml to review.
class AppAdditionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:owner)
    @root = Dir.mktmpdir
    @fleet = Tempfile.new([ "fleet", ".yml" ])
    File.write(@fleet.path, "servers:\n  nbg:\n    host: #{servers(:nbg).host}\n    apps:\n      storefront:\n        repo_path: /srv/storefront\n        destination: nbg\n        service: storefront\n")
    @settings = [ Rails.configuration.x.repos_root, Rails.configuration.x.fleet_file ]
    Rails.configuration.x.repos_root = @root
    Rails.configuration.x.fleet_file = @fleet.path
    repo("shop", "service: shop\nservers: [#{servers(:nbg).host}]\nproxy:\n  ssl: true\n  hosts: [shop.example.com]\n")
    repo("stray", "service: stray\nservers: [198.51.100.99]\n")
    repo("home", "service: home\nservers: [<%= ENV.fetch(\"HOME_SERVER\") %>]\n")
  end

  teardown do
    Rails.configuration.x.repos_root, Rails.configuration.x.fleet_file = @settings
    FileUtils.rm_rf(@root)
    @fleet.close!
  end

  def repo(path, deploy_yml)
    FileUtils.mkdir_p(File.join(@root, path, "config"))
    File.write(File.join(@root, path, "config/deploy.yml"), deploy_yml)
  end

  def shop_params(**app) = { repo: "shop", config: "config/deploy.yml", app: { name: "shop", domains: "shop.example.com", health_path: "/up", health_https: "1", **app } }

  test "the dashboard links to Add app" do
    get root_path
    assert_select "a[href=?]", repos_path, text: "Add app"
  end

  test "lists ready configs as links to the form, and says why the others can't be added" do
    get repos_path

    assert_select "a[href=?]", new_app_path(repo: "shop", config: "config/deploy.yml")
    assert_select ".repo-config--blocked", /stray.*198\.51\.100\.99, a server Grateful Deploy doesn't know/m
    assert_select "a[href=?]", new_app_path(repo: "stray", config: "config/deploy.yml"), false
  end

  test "the form is filled in from the config" do
    get new_app_path(repo: "shop", config: "config/deploy.yml")

    assert_select "input[name='app[name]'][value=shop]"
    assert_select "input[name='app[domains]'][value='shop.example.com']"
    assert_select "input[name='app[health_https]'][checked]"
    assert_select "select[name='app[server_id]']", false
    assert_select ".app-proposal", /nbg/
  end

  test "a server the ERB fills in is picked from the known ones, and its ENV settings are asked for" do
    get new_app_path(repo: "home", config: "config/deploy.yml")

    assert_select "select[name='app[server_id]'] option", servers(:nbg).name
    assert_select "input[name='app[kamal_env][HOME_SERVER]']"
  end

  test "an unknown server's config has no form" do
    get new_app_path(repo: "stray", config: "config/deploy.yml")

    assert_redirected_to repos_path
    assert_match(/doesn't know/, flash[:alert])
  end

  test "a repo or config the scan didn't find is not found" do
    get new_app_path(repo: "../etc", config: "config/deploy.yml")
    assert_response :not_found
    post apps_path, params: shop_params.merge(config: "config/deploy.prod.yml")
    assert_response :not_found
  end

  test "saving adds the app, writes it into fleet.yml and checks its status" do
    assert_enqueued_with(job: RefreshStatusJob) do
      assert_difference -> { servers(:nbg).apps.count } do
        post apps_path, params: shop_params
      end
    end
    app = servers(:nbg).apps.find_by!(name: "shop")

    assert_redirected_to app_path(app)
    assert_match(/config\/fleet\.yml/, flash[:notice])
    assert_equal [ File.join(@root, "shop"), %w[shop.example.com], true ], [ app.repo_path, app.domains, app.health_https? ]
    assert_equal "shop", YAML.load_file(@fleet.path).dig("servers", "nbg", "apps", "shop", "service")
  end

  test "a name in use shows the form again with the reason, and adds nothing" do
    assert_no_difference -> { App.count } do
      post apps_path, params: shop_params(name: "storefront")
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors", /Name/
    assert_not_includes File.read(@fleet.path), "shop"
  end

  test "if fleet.yml can't be written, the app is still added and the page says so" do
    File.delete(@fleet.path)
    post apps_path, params: shop_params

    assert servers(:nbg).apps.exists?(name: "shop")
    assert_match(/couldn't write config\/fleet\.yml/, flash[:alert])
  end

  test "a config that can't be added isn't saved, whatever the form sends" do
    assert_no_difference -> { App.count } do
      post apps_path, params: { repo: "stray", config: "config/deploy.yml", app: { name: "stray", server_id: servers(:nbg).id } }
    end
    assert_redirected_to repos_path
  end
end
