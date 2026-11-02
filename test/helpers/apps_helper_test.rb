require "test_helper"

class AppsHelperTest < ActionView::TestCase
  def snapshot(**attrs) = StatusSnapshot.new({ container_state: "running", checked_at: Time.current }.merge(attrs))

  test "health badge: healthy, down, or not checked yet" do
    assert_dom_equal %(<span class="health health--up">Healthy</span>), health_badge(snapshot(health_code: 200))
    assert_dom_equal %(<span class="health health--down">Down</span>), health_badge(snapshot(health_code: 502))
    assert_dom_equal %(<span class="health health--unknown">Not checked yet</span>), health_badge(nil)
  end

  test "a running app with no domain to check isn't shown as down" do
    running = snapshot(health_code: nil, error: HealthCheck::NO_DOMAIN)
    assert_dom_equal %(<span class="health health--unknown">Running · not health-checked</span>), health_badge(running)

    stopped = snapshot(container_state: "missing", health_code: nil, error: HealthCheck::NO_DOMAIN)
    assert_dom_equal %(<span class="health health--down">Down</span>), health_badge(stopped)
  end
end
