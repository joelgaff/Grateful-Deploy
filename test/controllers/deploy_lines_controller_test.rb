require "test_helper"

# Catch-up for a deploy page: the lines saved after the last one it shows.
class DeployLinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @deploy = apps(:storefront).deploys.create!(kind: "deploy", status: "running", log: "one\ntwo\nthree\n", log_lines: 3)
    sign_in_as users(:owner)
  end

  def lines_in_response
    css_select("turbo-stream[action=append][target='log_deploy_#{@deploy.id}'] template .log-line")
      .map { [ it["data-line"], it.text ] }
  end

  test "returns the lines after the last one the page shows, numbered" do
    get app_deploy_lines_path(@deploy.app, @deploy, after: 1), as: :turbo_stream

    assert_response :success
    assert_equal [ %w[2 two], %w[3 three] ], lines_in_response
  end

  test "nothing new means an empty catch-up" do
    get app_deploy_lines_path(@deploy.app, @deploy, after: 3), as: :turbo_stream

    assert_response :success
    assert_empty lines_in_response
  end

  test "a missing or odd 'after' sends every line" do
    get app_deploy_lines_path(@deploy.app, @deploy, after: "-5x"), as: :turbo_stream

    assert_equal %w[1 2 3], lines_in_response.map(&:first)
  end

  test "requires sign in" do
    delete session_path
    get app_deploy_lines_path(@deploy.app, @deploy, after: 0), as: :turbo_stream

    assert_response :redirect
  end

  test "also sends the current summary, so a missed status update is caught too" do
    @deploy.update!(status: "succeeded", started_at: 1.minute.ago, finished_at: Time.current, exit_code: 0)

    get app_deploy_lines_path(@deploy.app, @deploy, after: 3), as: :turbo_stream

    assert_turbo_stream action: "replace", target: "summary_deploy_#{@deploy.id}" do
      assert_select "[data-in-flight='false']"
      assert_select "dt", "Took"
    end
  end

  test "the summary says when the deploy is still in flight" do
    get app_deploy_lines_path(@deploy.app, @deploy, after: 3), as: :turbo_stream

    assert_turbo_stream action: "replace", target: "summary_deploy_#{@deploy.id}" do
      assert_select "[data-in-flight='true']"
    end
  end
end
