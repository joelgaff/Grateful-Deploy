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
end
