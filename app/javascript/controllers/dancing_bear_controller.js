import { Controller } from "@hotwired/stimulus"
import { FRAMES } from "bear/frames"
import { PALETTES } from "bear/palettes"

// The "working on it" sign: a pixel-art bear dancing on a <canvas class="bear">, one canvas
// pixel per sprite pixel, scaled up crisply by CSS (image-rendering: pixelated). Frames loop at
// `fps`; `paused`, or prefers-reduced-motion, holds it on frame 0. Colours: the `palette` value,
// else the palette named by `paletteName`, else the --bear-* CSS variables (the app theme).
export default class extends Controller {
  static values = {
    size: { type: Number, default: 128 },
    fps: { type: Number, default: 8 },
    paused: { type: Boolean, default: false },
    palette: { type: Object, default: {} },
    paletteName: { type: String, default: "" },
  }

  connect() {
    this.frame = 0
    this.element.width = 32
    this.element.height = 32
    this.pen = this.element.getContext("2d")
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.scheme = window.matchMedia("(prefers-color-scheme: dark)")
    this.restart = () => this.start()
    this.redraw = () => this.draw()
    this.motion.addEventListener("change", this.restart)
    this.scheme.addEventListener("change", this.redraw)
    this.start()
  }

  disconnect() {
    this.stop()
    this.motion.removeEventListener("change", this.restart)
    this.scheme.removeEventListener("change", this.redraw)
  }

  sizeValueChanged() {
    this.element.style.width = this.element.style.height = `${this.sizeValue}px`
  }

  fpsValueChanged() { if (this.pen) this.start() }
  pausedValueChanged() { if (this.pen) this.start() }
  paletteValueChanged() { if (this.pen) this.draw() }
  paletteNameValueChanged() { if (this.pen) this.draw() }

  start() {
    this.stop()
    if (this.pausedValue || this.motion.matches) this.frame = 0
    this.draw()
    if (this.pausedValue || this.motion.matches || this.fpsValue <= 0) return

    this.timer = setInterval(() => {
      this.frame = (this.frame + 1) % FRAMES.length
      this.draw()
    }, 1000 / this.fpsValue)
  }

  stop() {
    clearInterval(this.timer)
    this.timer = null
  }

  draw() {
    const colours = this.colours
    this.pen.clearRect(0, 0, 32, 32)
    FRAMES[this.frame].forEach((row, y) => {
      for (let x = 0; x < row.length; x++) {
        const colour = colours[row[x]]
        if (!colour) continue
        this.pen.fillStyle = colour
        this.pen.fillRect(x, y, 1, 1)
      }
    })
    this.element.dataset.frame = this.frame
  }

  get colours() {
    const style = getComputedStyle(this.element)
    const theme = {
      k: style.getPropertyValue("--bear-outline").trim() || PALETTES.grateful.k,
      b: style.getPropertyValue("--bear-body").trim() || PALETTES.grateful.b,
      y: style.getPropertyValue("--bear-collar").trim() || PALETTES.grateful.y,
    }
    return { ...theme, ...PALETTES[this.paletteNameValue], ...this.paletteValue }
  }
}
