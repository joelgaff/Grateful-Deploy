require "application_system_test_case"

# The deploy page's output: live lines, catch-up after the live connection
# (re)connects, the 5-second safety net, and order without duplicates.
class DeployLogTest < ApplicationSystemTestCase
  setup do
    @app = apps(:storefront)
    @deploy = @app.deploys.create!(kind: "deploy")
    @deploy.start!
    sign_in
    visit app_deploy_path(@app, @deploy)
    assert_selector "turbo-cable-stream-source[connected]", visible: false
  end

  test "lines stream in live, and the status updates when the deploy finishes" do
    %w[Building Pushing Booting].each { @deploy.append_line(it) }

    assert_equal %w[Building Pushing Booting], shown_lines
    @deploy.finish!(0)
    assert_selector "#status_deploy_#{@deploy.id}", text: "succeeded"
    assert_no_button "Cancel deploy"
  end

  test "lines saved while the live connection was down are caught up when it reconnects" do
    stop_safety_net
    @deploy.append_line("Building")
    assert_equal %w[Building], shown_lines

    page.execute_script("window.__source = document.querySelector('turbo-cable-stream-source'); window.__source.remove()")
    %w[Pushing Booting].each { save_without_live_update(it) }
    page.execute_script("document.body.append(window.__source)")

    assert_equal %w[Building Pushing Booting], shown_lines
  end

  test "lines whose live update was dropped show up within the 5-second safety net" do
    page.execute_script("document.querySelector('turbo-cable-stream-source').remove()")
    %w[Building Pushing].each { save_without_live_update(it) }

    assert_equal %w[Building Pushing], shown_lines(wait: 8)
  end

  test "a line that arrives live before missed ones goes in its place, and none shows twice" do
    stop_safety_net
    @deploy.append_line("one")
    @deploy.append_line("two")
    %w[three four].each { save_without_live_update(it) }
    @deploy.append_line("five")
    assert_equal %w[one two five], shown_lines(count: 3)

    page.execute_script("Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=log]'), 'log').catchUp()")

    assert_equal %w[one two three four five], shown_lines
  end

  private

  # The page's lines once it shows `count` of them (by default, all saved).
  def shown_lines(count: @deploy.reload.log_lines, wait: Capybara.default_max_wait_time)
    assert_selector "#log_deploy_#{@deploy.id} .log-line", count: count, wait: wait
    all("#log_deploy_#{@deploy.id} .log-line").map(&:text)
  end

  # As if the line's broadcast was lost: saved and numbered, never streamed.
  def save_without_live_update(line)
    Deploy.where(id: @deploy.id).update_all([ "log = log || ?, log_lines = log_lines + 1", "#{line}\n" ])
  end

  def stop_safety_net
    page.execute_script("clearInterval(Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-controller=log]'), 'log').safetyNet)")
  end
end
