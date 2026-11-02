require "application_system_test_case"

# The dancing bear is the "working on it" sign: it dances beside a deploy that is waiting or
# running and on the Deploy in progress button, drawn pixel by pixel from its palette, and holds
# still for people who ask for reduced motion.
class DancingBearTest < ApplicationSystemTestCase
  setup do
    @app = apps(:storefront)
    @deploy = @app.deploys.create!(kind: "deploy")
    @deploy.start!
  end

  # Emulated media stays on the browser between tests: put reduced motion back.
  teardown { page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: []) }

  test "a running deploy's status has a bear that dances" do
    sign_in
    visit app_deploy_path(@app, @deploy)

    assert_operator shown_frames.size, :>, 1, "the bear should move through its frames"
  end

  test "it is drawn from the palette, on a transparent background" do
    sign_in
    visit app_deploy_path(@app, @deploy)
    find("#summary_deploy_#{@deploy.id} canvas.bear[data-frame]")

    pixels = evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector("canvas.bear")
        const context = canvas.getContext("2d")
        return [context.getImageData(0, 0, 1, 1).data[3], getComputedStyle(canvas).imageRendering]
      })()
    JS
    assert_equal 0, pixels.first, "the corner is transparent"
    assert_equal "pixelated", pixels.last
  end

  test "the Deploy in progress button dances too" do
    sign_in
    visit app_path(@app)
    assert_selector "button[disabled] canvas.bear"
    assert_button "Deploy in progress", disabled: true
  end

  # In the box, where there's room: never squeezed into the status pill.
  test "on the dashboard it dances in the app's card until the deploy finishes" do
    sign_in
    visit root_path
    assert_selector "#card_app_#{@app.id} canvas.bear--corner"
    assert_no_selector ".status canvas.bear"

    @deploy.finish!(0)
    assert_selector "#status_deploy_#{@deploy.id}", text: "succeeded"
    assert_no_selector "#card_app_#{@app.id} canvas.bear"
  end

  test "on the deploy page it dances in the summary panel, not the status pill" do
    sign_in
    visit app_deploy_path(@app, @deploy)
    assert_selector "#summary_deploy_#{@deploy.id} .panel canvas.bear--corner"
    assert_no_selector ".status canvas.bear"
  end

  test "with reduced motion it holds still on its first frame" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    sign_in
    visit app_deploy_path(@app, @deploy)

    assert_equal [ "0" ], shown_frames
  end

  private

  # The frames the deploy summary's bear shows over about a second, read fresh each time: once
  # the live connection is up, so a late broadcast that redraws the summary can't swap the bear mid-read.
  def shown_frames
    assert_selector "turbo-cable-stream-source[connected]", visible: false
    find("#summary_deploy_#{@deploy.id} .panel canvas.bear[data-frame]")
    8.times.map do
      sleep 0.15
      evaluate_script("document.querySelector('#summary_deploy_#{@deploy.id} canvas.bear')?.dataset.frame")
    end.compact.uniq
  end
end
