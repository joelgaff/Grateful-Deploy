require "test_helper"

# One URL answers with plain text or a Turbo Stream depending on the Accept
# header, so a shared cache must be told the response varies on it (and on
# X-Requested-With, which Rails also uses to pick a format).
class ShipPreviewCachingTest < ActionDispatch::IntegrationTest
  setup do
    @app = apps(:storefront)
    @app.update!(repo_path: build_git_repo)
    sign_in_as users(:owner)
  end

  test "text and Turbo Stream answers tell caches they vary by Accept and X-Requested-With" do
    [ "text/plain", "text/vnd.turbo-stream.html" ].each do |accept|
      get app_ship_preview_path(@app), headers: { "Accept" => accept }

      assert_response :success
      vary = response.headers["Vary"].to_s.split(",").map { it.strip.downcase }
      assert_includes vary, "accept", "Accept #{accept}"
      assert_includes vary, "x-requested-with", "Accept #{accept}"
    end
  end
end
