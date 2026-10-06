// Pure helpers for the dock's name labels (components/DockLabel.qml and
// components/logic/DockLabelLogic.qml). Plain JS with no Qt globals, so the
// node tests run it in a vm context like DockModel.js.

var LABEL_MODES = ["off", "always", "hover"]
var LABEL_KINDS = ["all", "apps", "groups", "folders"]
var LABEL_FONTS = ["theme", "sans", "pixel"]
var LABEL_SIZES = ["small", "medium", "large"]
var LABEL_COLORS = ["theme", "high", "accent"]
var LABEL_BACKGROUNDS = ["none", "pill", "plate"]
var LABEL_REVEALS = ["slide", "typewriter", "scramble"]
var LABEL_EFFECTS = ["none", "glow", "shadow"]
var LABEL_MAX_WIDTH_MIN = 80
var LABEL_MAX_WIDTH_MAX = 240
var LABEL_MAX_WIDTH_DEFAULT = 140
var MAX_LABEL_NAMES = 200
var MAX_LABEL_NAME = 40
var MAX_LABEL_APP_ID = 128
var LABEL_CONFIG_KEYS = ["labelMode", "labelKind", "labelFont", "labelSize", "labelColor",
  "labelBackground", "labelReveal", "labelEffect", "labelMaxWidth", "labelNames"]
// The first label release spelled these; read once, dropped on save.
var LEGACY_LABEL_KEYS = ["showLabels", "labelPlacement", "labelContrast"]
var SCRAMBLE_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&*+=?"

function _pick(value, allowed, fallback) {
  return allowed.indexOf(value) >= 0 ? value : fallback
}

function _chars(s) { return Array.from(String(s == null ? "" : s)) }

// A name for an app without a desktop entry: the last part of its class id,
// words split on - and _, capitalised. "org.omarchy.terminal" -> "Terminal".
function prettyAppId(appId) {
  var s = String(appId == null ? "" : appId).trim()
  if (s === "") return ""
  if (/\.desktop$/i.test(s)) s = s.slice(0, -8)
  var parts = s.split(".")
  var last = parts[parts.length - 1] || s
  var words = last.split(/[-_\s]+/).filter(function(w) { return w !== "" })
  if (words.length === 0) return s
  return words.map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
}

// Drops what a short label can live without: bracketed parts and anything
// after a " - ", " — " or ": " subtitle separator.
function cleanName(name) {
  var orig = String(name == null ? "" : name).replace(/\s+/g, " ").trim()
  var s = orig
  var cut = s.search(/\s[-–—]\s|:\s/)
  if (cut > 0) s = s.slice(0, cut)
  s = s.replace(/\s*\([^)]*\)/g, "").replace(/\s+/g, " ").trim()
  return s !== "" ? s : orig
}

// The label text for a max width. fits(text) measures in the label's real
// font. Each step runs only when the previous one did not fit: the full
// name, the cleaned name, whole leading words, then an ellipsis inside the
// first word.
function shortenName(name, fits) {
  var full = String(name == null ? "" : name).replace(/\s+/g, " ").trim()
  if (full === "" || fits(full)) return { text: full, shortened: false }
  var clean = cleanName(full)
  if (fits(clean)) return { text: clean, shortened: true }
  var words = clean.split(" ")
  for (var n = words.length - 1; n >= 1; n--) {
    var head = words.slice(0, n).join(" ")
    if (fits(head)) return { text: head, shortened: true }
  }
  var chars = _chars(words[0])
  for (var k = chars.length - 1; k >= 1; k--) {
    var t = chars.slice(0, k).join("") + "…"
    if (fits(t)) return { text: t, shortened: true }
  }
  return { text: "…", shortened: true }
}

function labelVisible(mode, filter, kind) {
  if (mode !== "always" && mode !== "hover") return false
  return filter === "all" || filter === kind + "s"
}

// With a label shown, the tooltip appears only when it says more than the
// name: window previews, a state hint, or the full name of a shortened label.
function tooltipNeeded(labelShown, hasWindows, hasStateHint, shortened) {
  if (!labelShown) return true
  return !!(hasWindows || hasStateHint || shortened)
}

// The dock's per-slot label widths: { slot: { owner, width } }. A clear
// (width 0) only removes the entry its own owner wrote, so a tile leaving a
// slot cannot erase the tile that just moved in. Unchanged input returns the
// same object, so bindings on it do not re-run.
function withExtra(extras, slot, owner, width) {
  var cur = extras ? extras[slot] : undefined
  var w = Math.max(0, Math.round(Number(width) || 0))
  if (w > 0 && cur && cur.owner === owner && cur.width === w) return extras
  if (w === 0 && (!cur || cur.owner !== owner)) return extras
  var next = {}
  for (var k in extras) next[k] = extras[k]
  if (w > 0) next[slot] = { owner: owner, width: w }
  else delete next[slot]
  return next
}

function extrasBefore(extras, slot) {
  var sum = 0
  for (var k in extras) if (Number(k) < slot) sum += extras[k].width || 0
  return sum
}

function extrasTotal(extras) { return extrasBefore(extras, Infinity) }

// The card's x. A centred dock centres on its width without the hover-mode
// label widths, so a label opening on hover grows the dock away from its
// leading edge and the hovered icon stays under the pointer. Right-aligned
// docks keep their right edge (their labels open to the left).
function anchoredX(parentWidth, width, inset, alignment, hoverExtra) {
  if (alignment === "left") return inset
  if (alignment === "right") return parentWidth - width - inset
  return Math.round((parentWidth - (width - (hoverExtra || 0))) / 2)
}

// Row x of the icon centre in a tile that may carry a label.
function iconCentre(slotX, slotWidth, labelExtra, mirror) {
  var iconWidth = slotWidth - (labelExtra || 0)
  return slotX + (mirror ? (labelExtra || 0) : 0) + iconWidth / 2
}

function _noise(n) {
  var x = Math.sin(n * 12.9898) * 43758.5453
  return x - Math.floor(x)
}

// The text drawn at reveal progress t (0..1). Typewriter shows a growing
// prefix; scramble keeps the length and settles characters left to right,
// the rest drawn from SCRAMBLE_CHARS (deterministic for a seed and t).
function revealFrame(text, style, t, seed) {
  var chars = _chars(text)
  if (style !== "typewriter" && style !== "scramble") return chars.join("")
  var p = Math.max(0, Math.min(1, Number(t) || 0))
  var shown = Math.round(p * chars.length)
  if (style === "typewriter") return chars.slice(0, shown).join("")
  var step = Math.floor(p * 12)
  var out = ""
  for (var i = 0; i < chars.length; i++) {
    if (i < shown || chars[i] === " ") out += chars[i]
    else out += SCRAMBLE_CHARS.charAt(Math.floor(_noise(seed * 31 + i * 7 + step) * SCRAMBLE_CHARS.length))
  }
  return out
}

function _boundName(v) {
  return _chars(String(v).replace(/\s+/g, " ").trim()).slice(0, MAX_LABEL_NAME).join("")
}

// User label names from config: string to string, bounded like every other
// config list.
function boundLabelNames(value) {
  var out = {}
  if (!value || typeof value !== "object" || Array.isArray(value)) return out
  var n = 0
  for (var k in value) {
    if (n >= MAX_LABEL_NAMES) break
    if (!Object.prototype.hasOwnProperty.call(value, k)) continue
    if (k === "" || k === "__proto__" || k.length > MAX_LABEL_APP_ID) continue
    if (typeof value[k] !== "string") continue
    var name = _boundName(value[k])
    if (name === "") continue
    out[k] = name
    n++
  }
  return out
}

// A copy of names with appId set to name; a blank name removes the entry.
function withLabelName(names, appId, name) {
  var next = {}
  for (var k in names) next[k] = names[k]
  if (!appId) return next
  var v = _boundName(name == null ? "" : name)
  if (v === "") delete next[appId]
  else next[appId] = v
  return boundLabelNames(next)
}

function readLabelConfig(parsed) {
  var p = (parsed && typeof parsed === "object") ? parsed : {}
  var mode = _pick(p.labelMode, LABEL_MODES, "")
  if (mode === "") mode = p.showLabels === true ? "always" : "off"
  var color = _pick(p.labelColor, LABEL_COLORS, "")
  if (color === "") color = p.labelContrast === "high" ? "high" : "theme"
  var background = _pick(p.labelBackground, LABEL_BACKGROUNDS, "")
  if (background === "") background = p.labelContrast === "pill" ? "pill" : "none"
  var w = (typeof p.labelMaxWidth === "number" && isFinite(p.labelMaxWidth))
    ? Math.max(LABEL_MAX_WIDTH_MIN, Math.min(LABEL_MAX_WIDTH_MAX, Math.round(p.labelMaxWidth)))
    : LABEL_MAX_WIDTH_DEFAULT
  return {
    labelMode: mode,
    labelKind: _pick(p.labelKind, LABEL_KINDS, "all"),
    labelFont: _pick(p.labelFont, LABEL_FONTS, "theme"),
    labelSize: _pick(p.labelSize, LABEL_SIZES, "small"),
    labelColor: color,
    labelBackground: background,
    labelReveal: _pick(p.labelReveal, LABEL_REVEALS, "slide"),
    labelEffect: _pick(p.labelEffect, LABEL_EFFECTS, "none"),
    labelMaxWidth: w,
    labelNames: boundLabelNames(p.labelNames)
  }
}

function writeLabelConfig(conf, state) {
  for (var i = 0; i < LABEL_CONFIG_KEYS.length; i++) conf[LABEL_CONFIG_KEYS[i]] = state[LABEL_CONFIG_KEYS[i]]
  for (var j = 0; j < LEGACY_LABEL_KEYS.length; j++) delete conf[LEGACY_LABEL_KEYS[j]]
}
