// The dock's animation policy (Settings → Motion & Effects → Animations):
// one plan every Behavior and effect reads (Dock.motion), so a level change
// reaches all of them and no file keeps its own idea of "fast". Plain JS with
// no Qt globals, so the node tests run it in a vm context like DockLabels.js.
//
// Timings: fast for fades and colours, base for layout, row items and
// popups, slow for the autohide slide; hover and press keep the magnifier's
// and the press dip's own short timings. Easing: OutCubic entering, InCubic
// leaving (callers pick by direction).
//
//   layout    widths and positions ease (row items, dividers, the card)
//   scale     entering and leaving elements scale (0.6 to 1)
//   rise      popups and tooltips rise a few pixels as they appear
//   oneShots  launch/urgent bounce, pulse, glow ripple, glitch
//   reveal    label typewriter / scramble
//   fade      opacity eases (Reduced keeps only this)

var LEVELS = ["full", "reduced", "off"]

function normalizeLevel(v) {
  var s = String(v === undefined || v === null ? "" : v).toLowerCase()
  return LEVELS.indexOf(s) >= 0 ? s : "full"
}

function plan(level) {
  var l = normalizeLevel(level)
  var on = l !== "off"
  var full = l === "full"
  return {
    level: l,
    fast: on ? 120 : 0, base: on ? 180 : 0, slow: on ? 300 : 0,
    hover: on ? 110 : 0, press: on ? 90 : 0,
    layout: full, scale: full, rise: full, oneShots: full, reveal: full,
    fade: on
  }
}
