require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "an app's bear always dances in the same one of the five colours" do
    palette = bear_palette(apps(:storefront))

    assert_includes ApplicationHelper::BEAR_COLOURS, palette[:b]
    assert_equal palette, bear_palette(App.new(name: "storefront"))
  end

  test "the colours are spread across apps" do
    names = %w[blog docs storefront crm newsletter status shop notes]

    assert_operator names.map { bear_palette(App.new(name: it))[:b] }.uniq.size, :>, 2
  end

  test "Truckin' says what's running and which version" do
    app = apps(:storefront)
    sha = "3f1c9e2a" + "0" * 32

    assert_dom_equal %(<p class="truckin">Truckin'… deploying <span class="mono">3f1c9e2</span></p>),
      truckin(app.deploys.new(kind: "deploy", git_sha: sha))
    assert_dom_equal %(<p class="truckin">Truckin'… rolling back to <span class="mono">3f1c9e2</span></p>),
      truckin(app.deploys.new(kind: "rollback", version: sha))
    assert_dom_equal %(<p class="truckin">Truckin'… deploying</p>), truckin(app.deploys.new(kind: "deploy"))
  end
end
