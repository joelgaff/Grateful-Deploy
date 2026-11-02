import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Keeps a streaming log pinned to the newest line, unless the reader has
// scrolled up to look at something.
//
// With a catch-up URL (deploy logs, whose lines are saved and numbered), it
// also fills the gap between the page loading and its live stream
// connecting: once connected, it fetches the saved lines after the last one
// shown. Numbered lines, live or caught up, go in by number and are never
// shown twice, whichever arrives first.
//
// While the deploy is in flight it also catches up every 5 seconds, in case
// a live update was dropped (the catch-up refreshes the status too).
const SAFETY_NET_MS = 5_000

export default class extends Controller {
  static values = { catchUpUrl: String, summaryId: String }

  connect() {
    this.pinned = true
    this.scrollToBottom()
    this.observer = new MutationObserver(() => { if (this.pinned) this.scrollToBottom() })
    this.observer.observe(this.element, { childList: true })

    if (this.hasCatchUpUrlValue) {
      this.beforeStreamRender = this.beforeStreamRender.bind(this)
      document.addEventListener("turbo:before-stream-render", this.beforeStreamRender)
      this.catchUpWhenConnected()
      this.safetyNet = setInterval(() => { if (this.inFlight()) this.catchUp() }, SAFETY_NET_MS)
    }
  }

  disconnect() {
    this.observer.disconnect()
    this.streamObserver?.disconnect()
    clearInterval(this.safetyNet)
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender)
  }

  scroll() {
    const { scrollTop, scrollHeight, clientHeight } = this.element
    this.pinned = scrollHeight - scrollTop - clientHeight < 24
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }

  // Each <turbo-cable-stream-source> gets a "connected" attribute once its
  // subscription is live; catch up then (and again after a reconnect).
  catchUpWhenConnected() {
    const sources = [...document.querySelectorAll("turbo-cable-stream-source")]
    if (sources.some(source => source.hasAttribute("connected"))) this.catchUp()

    this.streamObserver = new MutationObserver(mutations => {
      if (mutations.some(m => m.target.hasAttribute("connected"))) this.catchUp()
    })
    sources.forEach(source => this.streamObserver.observe(source, { attributes: true, attributeFilter: ["connected"] }))
  }

  inFlight() {
    return document.getElementById(this.summaryIdValue)?.dataset.inFlight === "true"
  }

  async catchUp() {
    if (this.catchingUp) return
    this.catchingUp = true

    const url = new URL(this.catchUpUrlValue, window.location.href)
    url.searchParams.set("after", this.lastContiguousLine())
    try {
      const response = await fetch(url, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      if (response.ok) Turbo.renderStreamMessage(await response.text())
    } catch {
      // The next safety-net round tries again; a reload shows every saved line.
    } finally {
      this.catchingUp = false
    }
  }

  // The highest n such that lines 1..n are all on the page.
  lastContiguousLine() {
    const shown = new Set([...this.element.querySelectorAll("[data-line]")].map(el => Number(el.dataset.line)))
    let n = 0
    while (shown.has(n + 1)) n++
    return n
  }

  beforeStreamRender(event) {
    const stream = event.target
    if (stream.getAttribute("action") !== "append" || stream.getAttribute("target") !== this.element.id) return

    event.detail.render = (streamElement) => {
      for (const line of [...streamElement.templateContent.children]) this.insertInOrder(line)
    }
  }

  insertInOrder(line) {
    if (!line.dataset.line) return this.element.append(line)
    if (line.id && document.getElementById(line.id)) return

    const number = Number(line.dataset.line)
    const last = this.element.querySelector("[data-line]:last-child")
    if (!last || Number(last.dataset.line) < number) return this.element.append(line) // the usual case

    const later = [...this.element.querySelectorAll("[data-line]")].find(el => Number(el.dataset.line) > number)
    this.element.insertBefore(line, later || null)
  }
}
