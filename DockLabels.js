// Pure helpers for the dock's name labels (components/DockLabel.qml and
// components/logic/DockLabelLogic.qml). Plain JS with no Qt globals, so the
// node tests run it in a vm context like DockModel.js.

var LABEL_MODES = ["off", "always", "hover"]
var LABEL_KINDS = ["all", "apps", "groups", "folders"]
var LABEL_FONTS = ["theme", "sans", "pixel"]
var LABEL_SIZES = ["small", "medium", "large"]
var LABEL_WEIGHTS = ["regular", "medium", "bold"]
var LABEL_COLORS = ["auto", "theme", "accent"]
var LABEL_BACKGROUNDS = ["none", "pill", "plate"]
var LABEL_SHAPES = ["dock", "pill", "rounded", "square"]
var LABEL_INDICATORS = ["before", "after", "under"]
var LABEL_REVEALS = ["slide", "typewriter", "scramble"]
var LABEL_EFFECTS = ["none", "glow", "outline"]
var LABEL_MAX_WIDTH_MIN = 80
var LABEL_MAX_WIDTH_MAX = 240
var LABEL_MAX_WIDTH_DEFAULT = 140
var MAX_LABEL_NAMES = 200
var MAX_LABEL_NAME = 40
var MAX_LABEL_APP_ID = 128
var LABEL_CONFIG_KEYS = ["labelMode", "labelKind", "labelFont", "labelSize", "labelWeight",
  "labelColor", "labelBackground", "labelShape", "labelIndicators", "labelReveal", "labelEffect", "labelMaxWidth", "labelNames"]
// The first label release spelled these; read once, dropped on save.
var LEGACY_LABEL_KEYS = ["showLabels", "labelPlacement", "labelContrast"]
var SYMBOL_WORD = /^[&+\-–—|\/·:,.]+$/
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
    // A cut never ends on a connector like "&" or "-".
    if (SYMBOL_WORD.test(words[n - 1])) continue
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

// The dock's per-slot label widths: { slot: { owner, width, before } },
// where before is the part of width that sits ahead of the slot's own icon
// (a mirrored label, a side-indicator column). A clear (width 0) only
// removes the entry its own owner wrote, so a tile leaving a slot cannot
// erase the tile that just moved in. Unchanged input returns the same
// object, so bindings on it do not re-run.
function withExtra(extras, slot, owner, width, before) {
  var cur = extras ? extras[slot] : undefined
  var w = Math.max(0, Math.round(Number(width) || 0))
  var b = Math.max(0, Math.min(w, Math.round(Number(before) || 0)))
  if (w > 0 && cur && cur.owner === owner && cur.width === w && cur.before === b) return extras
  if (w === 0 && (!cur || cur.owner !== owner)) return extras
  var next = {}
  for (var k in extras) next[k] = extras[k]
  if (w > 0) next[slot] = { owner: owner, width: w, before: b }
  else delete next[slot]
  return next
}

function extrasBefore(extras, slot) {
  var sum = 0
  for (var k in extras) if (Number(k) < slot) sum += extras[k].width || 0
  return sum
}

function extrasTotal(extras) { return extrasBefore(extras, Infinity) }

// The card's x for its alignment. hoverExtra is width a centred dock leaves
// out of its centring (0 when nothing should grow one way only).
function anchoredX(parentWidth, width, inset, alignment, hoverExtra) {
  if (alignment === "left") return inset
  if (alignment === "right") return parentWidth - width - inset
  return Math.round((parentWidth - (width - (hoverExtra || 0))) / 2)
}

// Label width that sits before a slot's icon: every earlier slot's, plus
// the part of the slot's own that is ahead of its icon (includeOwn false
// for a slot index shared with an unlabelled item).
function homeExtra(extras, slot, includeOwn) {
  var own = (includeOwn !== false && extras && extras[slot]) ? (extras[slot].before || 0) : 0
  return extrasBefore(extras, slot) + own
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
  // A config without labelMode comes from the first label release (or has
  // no labels): its band-sized labelSize does not carry over.
  var legacy = _pick(p.labelMode, LABEL_MODES, "") === ""
  var mode = legacy ? (p.showLabels === true ? "always" : "off") : p.labelMode
  // "high" was this release's own early spelling of auto.
  var color = p.labelColor === "high" ? "auto" : _pick(p.labelColor, LABEL_COLORS, "")
  if (color === "") color = p.labelContrast === "theme" ? "theme" : "auto"
  var background = _pick(p.labelBackground, LABEL_BACKGROUNDS, "")
  if (background === "") background = p.labelContrast === "pill" ? "pill" : "none"
  var w = (typeof p.labelMaxWidth === "number" && isFinite(p.labelMaxWidth))
    ? Math.max(LABEL_MAX_WIDTH_MIN, Math.min(LABEL_MAX_WIDTH_MAX, Math.round(p.labelMaxWidth)))
    : LABEL_MAX_WIDTH_DEFAULT
  return {
    labelMode: mode,
    labelKind: _pick(p.labelKind, LABEL_KINDS, "all"),
    labelFont: _pick(p.labelFont, LABEL_FONTS, "theme"),
    labelSize: legacy ? "medium" : _pick(p.labelSize, LABEL_SIZES, "medium"),
    labelWeight: _pick(p.labelWeight, LABEL_WEIGHTS, "medium"),
    labelColor: color,
    labelBackground: background,
    labelShape: _pick(p.labelShape, LABEL_SHAPES, "dock"),
    labelIndicators: _pick(p.labelIndicators, LABEL_INDICATORS, "before"),
    labelReveal: _pick(p.labelReveal, LABEL_REVEALS, "slide"),
    labelEffect: p.labelEffect === "shadow" ? "outline" : _pick(p.labelEffect, LABEL_EFFECTS, "none"),
    labelMaxWidth: w,
    labelNames: boundLabelNames(p.labelNames)
  }
}

// Window indicators move from under the icon to a column at the plate's
// edge only for always-on plates: a hover label would make them jump as it
// opens and closes.
function sideMarks(mode, background, indicators) {
  return mode === "always" && background === "plate" && (indicators === "before" || indicators === "after")
}

// Corner radius of a label background of height h. "dock" keeps the
// dock's own corner-to-height ratio, so a square dock gets square labels
// and a pill dock pill ones.
function labelRadius(shape, h, dockRatio) {
  if (shape === "pill") return h / 2
  if (shape === "rounded") return h / 4
  if (shape === "square") return 0
  return Math.min(h / 2, h * Math.max(0, Number(dockRatio) || 0))
}

var LABEL_LOOK_KEYS = ["labelFont", "labelSize", "labelWeight", "labelColor",
  "labelBackground", "labelShape", "labelIndicators", "labelReveal", "labelEffect", "labelMaxWidth"]

// A preset's label look over the current one: known keys with valid
// values win, anything else keeps its current value. (readLabelConfig
// would treat a look without labelMode as a legacy config.)
function pickLabelLook(look, current) {
  var l = (look && typeof look === "object") ? look : {}
  var c = current || {}
  var out = {}
  var lists = { labelFont: LABEL_FONTS, labelSize: LABEL_SIZES, labelWeight: LABEL_WEIGHTS,
    labelColor: LABEL_COLORS, labelBackground: LABEL_BACKGROUNDS, labelShape: LABEL_SHAPES, labelIndicators: LABEL_INDICATORS,
    labelReveal: LABEL_REVEALS, labelEffect: LABEL_EFFECTS }
  for (var i = 0; i < LABEL_LOOK_KEYS.length; i++) {
    var k = LABEL_LOOK_KEYS[i]
    var v = l[k]
    if (k === "labelEffect" && v === "shadow") v = "outline"
    if (k === "labelColor" && v === "high") v = "auto"
    if (k === "labelMaxWidth") {
      out[k] = (typeof v === "number" && isFinite(v))
        ? Math.max(LABEL_MAX_WIDTH_MIN, Math.min(LABEL_MAX_WIDTH_MAX, Math.round(v))) : c[k]
    } else {
      out[k] = lists[k].indexOf(v) >= 0 ? v : c[k]
    }
  }
  return out
}

// Identity of the Labels page's name rows: only the apps and their default
// names, so window-title churn in the dock model does not rebuild them.
function nameRowsKey(rows) {
  return JSON.stringify((rows || []).map(function(r) { return [r.appId, r.auto] }))
}

// A pinned folder's own name; blank goes back to the directory's name.
// Bounded like DockModel.boundPinnedFolders (120 characters).
var MAX_FOLDER_LABEL = 120
function folderBaseName(path) {
  var p = String(path == null ? "" : path).replace(/\/+$/, "")
  if (p === "" || p === "~") return "Home"
  var parts = p.split("/")
  return parts[parts.length - 1] || "Folder"
}

function withFolderName(folders, path, name) {
  var list = folders || []
  var at = -1
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].path === path) { at = i; break }
  if (at < 0) return list
  var v = _chars(String(name == null ? "" : name).replace(/\s+/g, " ").trim()).slice(0, MAX_FOLDER_LABEL).join("")
  var next = list.slice()
  var entry = {}
  for (var k in list[at]) entry[k] = list[at][k]
  entry.name = v !== "" ? v : folderBaseName(path)
  next[at] = entry
  return next
}

function writeLabelConfig(conf, state) {
  for (var i = 0; i < LABEL_CONFIG_KEYS.length; i++) conf[LABEL_CONFIG_KEYS[i]] = state[LABEL_CONFIG_KEYS[i]]
  for (var j = 0; j < LEGACY_LABEL_KEYS.length; j++) delete conf[LEGACY_LABEL_KEYS[j]]
}
