// Colours for the dancing bear's three pixel kinds: k outline, b body, y collar.
// The bear uses Grateful Deploy's own colours by default: --bear-outline, --bear-body and
// --bear-collar in application.css (light and dark). To recolour it everywhere, edit those
// variables; for one bear, pass a palette (data-dancing-bear-palette-value='{"b":"#c00"}') or a
// palette name (data-dancing-bear-palette-name-value="classic").
export const PALETTES = {
  // The bear as drawn, in the app's greys (the light theme's values of the CSS variables).
  grateful: { k: "#14141e", b: "#7d808a", y: "#d2d5db" },
  // The original blue bear with a yellow collar.
  classic: { k: "#14141e", b: "#1e5ac8", y: "#ffd600" },
}

export const PALETTE = PALETTES.classic
