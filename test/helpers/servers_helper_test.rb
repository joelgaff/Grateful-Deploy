require "test_helper"

class ServersHelperTest < ActionView::TestCase
  test "meter colors by how full it is" do
    assert_includes meter("RAM", 50, 100, modifier: "memory"), "meter--ok"
    assert_includes meter("RAM", 80, 100, modifier: "memory"), "meter--warn"
    assert_includes meter("RAM", 95, 100, modifier: "memory"), "meter--high"
  end

  test "no meter without numbers" do
    assert_nil meter("Swap", nil, 100, modifier: "swap")
    assert_nil meter("Swap", 0, 0, modifier: "swap")
  end
end
