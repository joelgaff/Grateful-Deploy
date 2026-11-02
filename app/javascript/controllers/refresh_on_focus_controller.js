import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const MIN_INTERVAL_MS = 10_000

// Re-renders this element from a turbo stream URL when you come back to the
// tab, e.g. after committing in a terminal. At most once every 10 seconds;
// a failed refresh (offline, server restarting) is skipped quietly.
let lastRefresh = 0

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.refresh = this.refresh.bind(this)
    window.addEventListener("focus", this.refresh)
  }

  disconnect() {
    window.removeEventListener("focus", this.refresh)
  }

  async refresh() {
    if (Date.now() - lastRefresh < MIN_INTERVAL_MS) return
    lastRefresh = Date.now()

    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      if (response.ok) Turbo.renderStreamMessage(await response.text())
    } catch {
      // Try again on the next focus.
    }
  }
}
