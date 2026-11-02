// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// A button with data-confirm-url asks the server for its confirm text at the
// moment it's clicked, so the Deploy confirm names the commit Kamal will build
// even if you committed after the page loaded.
Turbo.config.forms.confirm = async (message, form, submitter) => {
  const url = submitter?.dataset.confirmUrl || form.dataset.confirmUrl
  return confirm(url ? await freshMessage(url, message) : message)
}

async function freshMessage(url, fallback) {
  try {
    const response = await fetch(url, { headers: { Accept: "text/plain" } })
    if (response.ok) return await response.text()
  } catch {}
  return `${fallback}\n\n(Couldn't refresh this; it may be out of date.)`
}
