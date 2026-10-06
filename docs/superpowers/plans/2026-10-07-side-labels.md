# Side Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace upstream's below/above name labels with labels beside the icon (always on or revealed on hover), suppress redundant tooltips, and give labels their own look options.

**Architecture:** Pure helpers in a new `DockLabels.js` (node-tested); policy in `components/logic/DockLabelLogic.qml`; one visual `components/DockLabel.qml` per tile that measures, shortens, animates and reports the width it adds (`extra`) to a per-slot registry on the dock root. The registry feeds the zoom/wave home centres and the card's hover anchor. Settings move to a new Labels page.

**Tech Stack:** QML (Qt 6, Quickshell 0.3.1), plain ES5-ish JS loaded both by QML and node `vm`, node:test, Python static checks.

**Spec:** `docs/superpowers/specs/2026-10-07-side-labels-design.md` (on `priard`; read it with `git show priard:docs/superpowers/specs/2026-10-07-side-labels-design.md` while on the feature branch).

## Global Constraints

- Branch `feat/side-labels` cut from `upstream/experimental`, worked on in the live checkout (`~/.config/omarchy/plugins/omadock`). Every file write reloads the dock for ~0.5 s.
- **No upstream PR** until the user says so. Finish = merge into `priard` + `git push fork priard feat/side-labels`.
- Never put `FORK.md`, manifest version, `docs/superpowers/` or `CLAUDE.md` on the feature branch.
- No AI attribution in commits. One topic per commit, body explains why.
- Code, comments, commits in English.
- Ratchets (`tests/static/structure-check.py`): `Dock.qml` ≤ 2438 lines, `DockModel.js` ≤ 1529 lines, every other `.qml/.js/.mjs` ≤ 800 lines; `components/logic/*.qml` contain no Timer/Rectangle/Loader/etc. and every function takes `root` first.
- `Text` items use `textFormat: Text.PlainText` (security grep).
- Config keys and values exactly as the spec table: `labelMode` off|always|hover (default off), `labelKind` all|apps|groups|folders (all), `labelFont` theme|sans|pixel (theme), `labelSize` small|medium|large (small), `labelColor` theme|high|accent (theme), `labelBackground` none|pill|plate (none), `labelReveal` slide|typewriter|scramble (slide), `labelEffect` none|glow|shadow (none), `labelMaxWidth` 80–240 (140), `labelNames` ≤ 200 entries, names ≤ 40 chars.
- **Deviation from spec, agreed at hand-off:** font option `mono` becomes `sans` (Omarchy's theme font already is JetBrains Mono); the label is a sibling of the icon's `HoverFx` that mirrors its lift and reacts to glitch/glow, not a child of it; renaming lives on the Settings → Labels page (the context menu row opens it), because the context menu window takes no keyboard focus.
- CI-equivalent check set on the feature branch (fork-only `tests/run-all.sh` is absent there):
  `node --check DockModel.js && node --check DockLabels.js && node --test tests/unit/*.test.js tests/unit/*.test.mjs && python3 tests/static/structure-check.py && python3 tests/static/security-grep.py && /usr/lib/qt6/bin/qmllint --silent Dock.qml DockHost.qml components/*.qml components/settings/*.qml components/logic/*.qml`
  Referred to below as **CHECKS**.
- Live load check after every QML task: `bash tests/smoke-test.sh` (add `--restart` when a new file or IPC changed) and `journalctl --user --since "-20 s" | grep -iE "omadock/|qml"` must show no new errors.

## Review Focus

1. Pointer sweeping across a hover-mode dock: the hovered icon must never move under the pointer (no open/close oscillation) — pinned by `anchoredX` unit tests (Task 1) and the live sweep check (Task 8).
2. Dragging an app while labels are on: drop gap and group/merge targets must follow the icon, not the middle of a wide tile; labels must not open during a drag — Task 3 unit tests on `iconCentre`, Task 5 `wantOpen` requires `dragAppId === ""`.
3. Items appearing, disappearing or reordering (app launch/quit, pin/unpin, group edits) must not leave stale widths in the registry, or a neighbour's zoom/wave centre drifts — `withExtra` ownership tests (Task 1) and destruction cleanup (Task 4).
4. Hostile or odd names: empty, whitespace only, one huge word, emoji/CJK, `__proto__` as an app id in `labelNames` — `shortenName` / `boundLabelNames` tests (Task 1).
5. Old configs: `showLabels:true` with `labelPlacement:"above"` and `labelContrast:"pill"` must come up as an always-on side label with a pill, and the old keys must disappear on the next save — `readLabelConfig` / `writeLabelConfig` tests (Task 1).

---

### Task 0: Branch

- [ ] **Step 1: Cut the branch in the live checkout**

```bash
cd ~/.config/omarchy/plugins/omadock
git status --short            # must be empty
git fetch upstream
git switch -c feat/side-labels upstream/experimental
bash tests/smoke-test.sh --restart
```
Expected: `SMOKE TEST PASSED`. (`priard` currently equals `upstream/experimental` plus fork-only files, so the running dock is unchanged.)

---

### Task 1: `DockLabels.js` pure helpers

**Files:**
- Create: `DockLabels.js`
- Create: `tests/unit/labels.test.mjs`
- Modify: `.github/workflows/ci.yml` (add `node --check DockLabels.js` next to the DockModel syntax step)

**Interfaces:**
- Produces (global functions in `DockLabels.js`, used by QML as `DockLabels.x`):
  - `prettyAppId(appId: string): string`
  - `cleanName(name: string): string`
  - `shortenName(name: string, fits: (s: string) => bool): { text: string, shortened: bool }`
  - `labelVisible(mode: string, filter: string, kind: "app"|"group"|"folder"): bool`
  - `tooltipNeeded(labelShown: bool, hasWindows: bool, hasStateHint: bool, shortened: bool): bool`
  - `withExtra(extras: object, slot: int, owner: string, width: number): object` (returns the same object when nothing changes)
  - `extrasBefore(extras: object, slot: int): number`, `extrasTotal(extras: object): number`
  - `anchoredX(parentWidth, width, inset, alignment: string, hoverExtra): number`
  - `iconCentre(slotX, slotWidth, labelExtra, mirror: bool): number`
  - `revealFrame(text: string, style: string, t: number, seed: number): string`
  - `boundLabelNames(value): object`, `withLabelName(names: object, appId: string, name: string): object`
  - `readLabelConfig(parsed): object` (all ten label keys), `writeLabelConfig(conf: object, state: object): void`
  - constants `LABEL_MAX_WIDTH_MIN = 80`, `LABEL_MAX_WIDTH_MAX = 240`, `MAX_LABEL_NAME = 40`

- [ ] **Step 1: Write the failing tests** — `tests/unit/labels.test.mjs`:

```js
// Tests for DockLabels.js, the pure helpers behind the dock's name labels.
// Plain JS with no Qt globals, run in a vm context like DockModel.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKLABELS || new URL("../../DockLabels.js", import.meta.url)
const L = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), L)
const plain = (v) => JSON.parse(JSON.stringify(v))
// 7 px per character, like a monospace caption.
const fitsChars = (n) => (s) => Array.from(s).length * 7 <= n * 7

test("prettyAppId turns class ids into names", () => {
  assert.equal(L.prettyAppId("org.omarchy.terminal"), "Terminal")
  assert.equal(L.prettyAppId("zen-browser"), "Zen Browser")
  assert.equal(L.prettyAppId("com.github.foo_bar"), "Foo Bar")
  assert.equal(L.prettyAppId("signal.desktop"), "Signal")
  assert.equal(L.prettyAppId(""), "")
  assert.equal(L.prettyAppId(null), "")
})

test("cleanName drops brackets and subtitles", () => {
  assert.equal(L.cleanName("Signal - Private Messenger"), "Signal")
  assert.equal(L.cleanName("Firefox (Beta)"), "Firefox")
  assert.equal(L.cleanName("GIMP: Image Editor"), "GIMP")
  assert.equal(L.cleanName("Visual Studio Code — Insiders"), "Visual Studio Code")
  assert.equal(L.cleanName("(only brackets)"), "(only brackets)")
})

test("shortenName keeps names that fit", () => {
  assert.deepEqual(plain(L.shortenName("Signal", fitsChars(10))), { text: "Signal", shortened: false })
})

test("shortenName cleans before cutting", () => {
  assert.deepEqual(plain(L.shortenName("Signal - Private Messenger", fitsChars(10))), { text: "Signal", shortened: true })
})

test("shortenName cuts at word boundaries without an ellipsis", () => {
  assert.deepEqual(plain(L.shortenName("Visual Studio Code", fitsChars(14))), { text: "Visual Studio", shortened: true })
  assert.deepEqual(plain(L.shortenName("Zen Browser", fitsChars(5))), { text: "Zen", shortened: true })
})

test("shortenName ellipsises only a first word that does not fit", () => {
  assert.deepEqual(plain(L.shortenName("Spotifasolatron", fitsChars(8))), { text: "Spotifa…", shortened: true })
})

test("shortenName handles empty, blank, tiny widths and wide characters", () => {
  assert.deepEqual(plain(L.shortenName("", fitsChars(8))), { text: "", shortened: false })
  assert.deepEqual(plain(L.shortenName("   ", fitsChars(8))), { text: "", shortened: false })
  assert.deepEqual(plain(L.shortenName("Mattermost", () => false)), { text: "…", shortened: true })
  assert.equal(L.shortenName("日本語のアプリ名前", fitsChars(4)).text, "日本語…")
  assert.equal(L.shortenName("🎵🎵🎵🎵🎵🎵", fitsChars(3)).text, "🎵🎵…")
})

test("labelVisible follows mode and filter", () => {
  assert.equal(L.labelVisible("off", "all", "app"), false)
  assert.equal(L.labelVisible("always", "all", "folder"), true)
  assert.equal(L.labelVisible("hover", "apps", "app"), true)
  assert.equal(L.labelVisible("hover", "apps", "group"), false)
  assert.equal(L.labelVisible("always", "folders", "folder"), true)
  assert.equal(L.labelVisible("bogus", "all", "app"), false)
})

test("tooltipNeeded only when the tooltip says more than the label", () => {
  assert.equal(L.tooltipNeeded(false, false, false, false), true)
  assert.equal(L.tooltipNeeded(true, false, false, false), false)
  assert.equal(L.tooltipNeeded(true, true, false, false), true)
  assert.equal(L.tooltipNeeded(true, false, true, false), true)
  assert.equal(L.tooltipNeeded(true, false, false, true), true)
})

test("withExtra records, updates and clears by owner", () => {
  let e = {}
  e = L.withExtra(e, 2, "a", 40)
  e = L.withExtra(e, 0, "b", 10)
  assert.equal(L.extrasBefore(e, 2), 10)
  assert.equal(L.extrasBefore(e, 3), 50)
  assert.equal(L.extrasTotal(e), 50)
  const same = L.withExtra(e, 2, "a", 40)
  assert.equal(same, e)
  // Another owner moved into slot 2 first: a's late clear must not erase it.
  e = L.withExtra(e, 2, "c", 30)
  e = L.withExtra(e, 2, "a", 0)
  assert.equal(L.extrasTotal(e), 40)
  e = L.withExtra(e, 2, "c", 0)
  assert.equal(L.extrasTotal(e), 10)
  assert.equal(L.withExtra({}, 5, "x", 0) !== undefined, true)
})

test("anchoredX keeps a centred dock's leading edge while labels open", () => {
  // 1000 wide screen, dock 200 wide at rest -> x 400.
  assert.equal(L.anchoredX(1000, 200, 20, "center", 0), 400)
  // A hover label adds 80: same x, the dock grows to the right.
  assert.equal(L.anchoredX(1000, 280, 20, "center", 80), 400)
  // Always-mode width is not hover extra: it centres.
  assert.equal(L.anchoredX(1000, 280, 20, "center", 0), 360)
  assert.equal(L.anchoredX(1000, 280, 20, "left", 80), 20)
  // Right: the right edge stays (labels open to the left there).
  assert.equal(L.anchoredX(1000, 280, 20, "right", 80), 700)
})

test("iconCentre finds the icon in a wide tile", () => {
  assert.equal(L.iconCentre(100, 60, 0, false), 130)
  assert.equal(L.iconCentre(100, 160, 100, false), 130)
  assert.equal(L.iconCentre(100, 160, 100, true), 230)
})

test("revealFrame types and scrambles without changing length", () => {
  assert.equal(L.revealFrame("Signal", "slide", 0.2, 1), "Signal")
  assert.equal(L.revealFrame("Signal", "typewriter", 0, 1), "")
  assert.equal(L.revealFrame("Signal", "typewriter", 0.5, 1), "Sig")
  assert.equal(L.revealFrame("Signal", "typewriter", 1, 1), "Signal")
  const s = L.revealFrame("Zen Browser", "scramble", 0.3, 7)
  assert.equal(Array.from(s).length, 11)
  assert.equal(s.slice(0, 3), "Zen")
  assert.equal(s.charAt(3), " ")
  assert.equal(L.revealFrame("Zen Browser", "scramble", 1, 7), "Zen Browser")
  assert.equal(L.revealFrame("Zen", "scramble", 0.3, 7), L.revealFrame("Zen", "scramble", 0.3, 7))
})

test("boundLabelNames keeps sane string entries only", () => {
  const raw = JSON.parse('{"a":"  Matter  most ","b":"","c":5,"__proto__":"x","' + "z".repeat(200) + '":"long id"}')
  raw.d = "x".repeat(60)
  const out = plain(L.boundLabelNames(raw))
  assert.deepEqual(Object.keys(out).sort(), ["a", "d"])
  assert.equal(out.a, "Matter most")
  assert.equal(out.d.length, 40)
  assert.deepEqual(plain(L.boundLabelNames(["x"])), {})
  assert.deepEqual(plain(L.boundLabelNames(null)), {})
  const many = {}
  for (let i = 0; i < 300; i++) many["app" + i] = "n" + i
  assert.equal(Object.keys(L.boundLabelNames(many)).length, 200)
})

test("withLabelName sets, trims and clears", () => {
  let n = L.withLabelName({}, "zen", "  Zen ")
  assert.deepEqual(plain(n), { zen: "Zen" })
  n = L.withLabelName(n, "zen", "   ")
  assert.deepEqual(plain(n), {})
  assert.deepEqual(plain(L.withLabelName({}, "", "x")), {})
})

test("readLabelConfig defaults", () => {
  assert.deepEqual(plain(L.readLabelConfig(null)), {
    labelMode: "off", labelKind: "all", labelFont: "theme", labelSize: "small",
    labelColor: "theme", labelBackground: "none", labelReveal: "slide",
    labelEffect: "none", labelMaxWidth: 140, labelNames: {}
  })
})

test("readLabelConfig migrates upstream's first label keys", () => {
  const c = L.readLabelConfig({ showLabels: true, labelPlacement: "above", labelContrast: "pill", labelSize: "large" })
  assert.equal(c.labelMode, "always")
  assert.equal(c.labelBackground, "pill")
  assert.equal(c.labelColor, "theme")
  assert.equal(c.labelSize, "large")
  assert.equal(L.readLabelConfig({ showLabels: true, labelContrast: "high" }).labelColor, "high")
  assert.equal(L.readLabelConfig({ showLabels: false }).labelMode, "off")
  // New keys win over old ones.
  assert.equal(L.readLabelConfig({ showLabels: true, labelMode: "hover" }).labelMode, "hover")
})

test("readLabelConfig validates values", () => {
  const c = L.readLabelConfig({ labelMode: "sideways", labelFont: "comic", labelMaxWidth: 9999, labelEffect: "glow" })
  assert.equal(c.labelMode, "off")
  assert.equal(c.labelFont, "theme")
  assert.equal(c.labelMaxWidth, 240)
  assert.equal(c.labelEffect, "glow")
  assert.equal(L.readLabelConfig({ labelMaxWidth: 10 }).labelMaxWidth, 80)
  assert.equal(L.readLabelConfig({ labelMaxWidth: "150" }).labelMaxWidth, 140)
  assert.equal(L.readLabelConfig({ labelMaxWidth: 151.6 }).labelMaxWidth, 152)
})

test("writeLabelConfig writes new keys and drops old ones", () => {
  const conf = { showLabels: true, labelPlacement: "below", labelContrast: "pill", other: 1 }
  const state = L.readLabelConfig({ labelMode: "hover", labelNames: { a: "A" } })
  L.writeLabelConfig(conf, state)
  assert.equal(conf.showLabels, undefined)
  assert.equal(conf.labelPlacement, undefined)
  assert.equal(conf.labelContrast, undefined)
  assert.equal(conf.labelMode, "hover")
  assert.deepEqual(plain(conf.labelNames), { a: "A" })
  assert.equal(conf.other, 1)
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test tests/unit/labels.test.mjs`
Expected: FAIL (`ENOENT ... DockLabels.js`).

- [ ] **Step 3: Implement** — `DockLabels.js`:

```js
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
```

Then in `.github/workflows/ci.yml` change the syntax step:

```yaml
      - name: DockModel syntax
        run: node --check DockModel.js && node --check DockLabels.js
```

- [ ] **Step 4: Run tests**

Run: `node --test tests/unit/labels.test.mjs`
Expected: all PASS. Then run **CHECKS** — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add DockLabels.js tests/unit/labels.test.mjs .github/workflows/ci.yml
git commit -m "feat(labels): pure helpers for side labels

Name shortening (clean, whole words, then ellipsis), class-id fallback
names, the per-slot width registry with owner-checked clears, the hover
anchor, reveal frames and the label config reader with migration from
showLabels/labelPlacement/labelContrast. Kept free of Qt so node tests
cover every edge case the QML relies on."
```

---

### Task 2: Config, root state, presets, policy module

**Files:**
- Modify: `Dock.qml` (label properties ~886-891, label functions ~1882-1884, blank lines in the setter block ~1831-1880)
- Modify: `components/logic/DockConfigLogic.qml:140-145` and `:236-240`, add import
- Modify: `components/logic/DockLabelLogic.qml` (rewrite)
- Modify: `DockModel.js:819` (`LOOK_KEYS`, same line count)
- Modify: `components/logic/DockStyleLogic.qml:28-36` (`slotHomeCenter`)
- Test: `tests/unit/dockmodel.test.mjs` (pickLook)

**Interfaces:**
- Consumes: Task 1 `readLabelConfig`, `writeLabelConfig`, `labelVisible`, `prettyAppId`, `tooltipNeeded`, `withExtra`, `extrasBefore`, `extrasTotal`, `withLabelName`.
- Produces on the dock root (`Dock.qml`):
  - properties `labelMode, labelKind, labelFont, labelSize, labelColor, labelBackground, labelReveal, labelEffect` (string), `labelMaxWidth` (int), `labelNames` (var), `labelExtras` (var), `labelsOpen` (int), `labelEditAppId` (string), `readonly labelHoverExtra` (real)
  - `labelStyle(kind) -> { show, hover, mirror, fontPx, family, ink, background, reveal, effect, maxWidth }`
  - `labelName(appId, name) -> string`
  - `labelTooltipNeeded(kind, hasWindows, hasStateHint, shortened) -> bool`
  - `labelExtraBefore(slot) -> real`, `setLabelExtra(slot, owner, width)`
  - `setLabelName(appId, name)`, `openLabelRename(appId)`, `labelNameRows() -> [{ appId, name, auto }]`
  - `slotHomeCenter` now adds `labelExtraBefore(slotsBefore)`.

- [ ] **Step 1: Failing test for presets** — append to `tests/unit/dockmodel.test.mjs`:

```js
test("pickLook carries the label look keys but not behaviour or names", () => {
  const look = plain(M.pickLook({
    labelFont: "pixel", labelSize: "large", labelColor: "accent", labelBackground: "plate",
    labelReveal: "scramble", labelEffect: "glow", labelMaxWidth: 180,
    labelMode: "hover", labelKind: "apps", labelNames: { a: "A" }
  }))
  assert.deepEqual(look, {
    labelFont: "pixel", labelSize: "large", labelColor: "accent", labelBackground: "plate",
    labelReveal: "scramble", labelEffect: "glow", labelMaxWidth: 180
  })
})
```

Run: `node --test tests/unit/dockmodel.test.mjs` — Expected: FAIL on that test.

- [ ] **Step 2: `LOOK_KEYS`** — edit `DockModel.js` line 819 in place (do not add a line; the file sits at its ratchet):

```js
  "groupIconEffects", "folderColor", "iconSize", "itemSpacing", "sectionSpacing", "labelFont", "labelSize", "labelColor", "labelBackground", "labelReveal", "labelEffect", "labelMaxWidth"
```

Run: `node --test tests/unit/dockmodel.test.mjs` — Expected: PASS. (If `pickLook` drops numbers other than known ones, check its number branch and fix there, still without adding lines.)

- [ ] **Step 3: Root properties** — in `Dock.qml` replace the block

```qml
  // ---- name labels on the tiles (policy in DockLabelLogic)
  property bool showLabels: false
  property string labelKind: "all"        // all | apps | groups | folders
  property string labelPlacement: "below" // below | above
  property string labelSize: "small"      // small | medium | large
  property string labelContrast: "theme"  // theme | high | pill
```

with

```qml
  // ---- name labels beside the icons (DockLabelLogic, DockLabels.js)
  property string labelMode: "off"        // off | always | hover
  property string labelKind: "all"        // all | apps | groups | folders
  property string labelFont: "theme"      // theme | sans | pixel
  property string labelSize: "small"      // small | medium | large
  property string labelColor: "theme"     // theme | high | accent
  property string labelBackground: "none" // none | pill | plate
  property string labelReveal: "slide"    // slide | typewriter | scramble
  property string labelEffect: "none"     // none | glow | shadow
  property int labelMaxWidth: 140
  property var labelNames: ({})           // appId -> the user's label text
  property var labelExtras: ({})          // slot -> { owner, width } (DockLabels.withExtra)
  property int labelsOpen: 0              // hover-mode labels open or closing
  property string labelEditAppId: ""      // app the Labels page should focus
  readonly property real labelHoverExtra: labelLogic.hoverExtra(root)
```

and replace

```qml
  // Name labels: rendering policy (visibility, size, contrast, band)
  function labelStyle(kind) { return labelLogic.style(root, kind) }
  function labelBandHeight() { return labelLogic.bandHeight(root) }
```

with

```qml
  // Name labels: rendering policy and the per-slot width registry
  function labelStyle(kind) { return labelLogic.style(root, kind) }
  function labelName(appId, name) { return labelLogic.displayName(root, appId, name) }
  function labelTooltipNeeded(kind, wins, hint, shortened) { return labelLogic.tooltipNeeded(root, kind, wins, hint, shortened) }
  function labelExtraBefore(slot) { return labelLogic.extraBefore(root, slot) }
  function setLabelExtra(slot, owner, width) { labelLogic.setExtra(root, slot, owner, width) }
  function setLabelName(appId, name) { labelLogic.setName(root, appId, name) }
  function openLabelRename(appId) { labelLogic.openRename(root, appId) }
  function labelNameRows() { return labelLogic.nameRows(root) }
```

Then pay the ratchet: delete blank lines between consecutive one-line wrapper functions in the `function setOption … function setUrgentSoundName` block (Dock.qml ~1831-1856, and further one-liner runs if needed) until `wc -l Dock.qml` prints ≤ 2438. Do not delete blank lines that separate commented sections.

- [ ] **Step 4: Config read/write** — `components/logic/DockConfigLogic.qml`: add `import "../../DockLabels.js" as DockLabels` after the existing imports; replace lines 140-145:

```qml
    // Name labels (DockLabels.readLabelConfig), including the first release's
    // showLabels / labelPlacement / labelContrast spellings.
    var labels = DockLabels.readLabelConfig(parsed)
    for (var lk in labels) root[lk] = labels[lk]
```

and lines 236-240:

```qml
    DockLabels.writeLabelConfig(conf, root)
```

- [ ] **Step 5: Policy module** — replace `components/logic/DockLabelLogic.qml` entirely:

```qml
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../../DockLabels.js" as DockLabels

// Logic module: name-label policy for dock tiles (apps, app groups,
// folders). style() is everything one DockLabel needs; the width registry
// (root.labelExtras) is what lets zoom/wave centres and the card's hover
// anchor account for labels. Helpers with no Qt in them live in DockLabels.js.

QtObject {
  function style(root, kind) {
    var show = !!root && DockLabels.labelVisible(root.labelMode, root.labelKind, kind)
    var pixel = !!root && root.labelFont === "pixel"
    var base = Style.font.caption
    // Silkscreen is drawn on an 8 px grid; other fonts follow the theme scale.
    var sizes = pixel ? { small: 8, medium: 12, large: 16 } : { small: base - 2, medium: base, large: base + 2 }
    var ink = root ? root.dockForeground : Color.bar.text
    if (root && root.labelColor === "high") ink = root.blackOrWhiteOn(Color.bar.background)
    else if (root && root.labelColor === "accent") ink = Color.accent
    return {
      show: show,
      hover: !!root && root.labelMode === "hover",
      mirror: !!root && root.alignment === "right",
      fontPx: sizes[root ? root.labelSize : "small"] || sizes.small,
      family: pixel ? "Silkscreen" : ((root && root.labelFont === "sans") ? "sans-serif" : Style.font.family),
      ink: ink,
      background: root ? root.labelBackground : "none",
      reveal: root ? root.labelReveal : "slide",
      effect: root ? root.labelEffect : "none",
      maxWidth: root ? root.labelMaxWidth : 140
    }
  }

  // The user's name wins; an app without a desktop entry (its name is its
  // class id) gets a readable one.
  function displayName(root, appId, name) {
    var custom = (root && appId && root.labelNames) ? root.labelNames[appId] : undefined
    if (typeof custom === "string" && custom !== "") return custom
    if (appId && (name === "" || name === appId)) return DockLabels.prettyAppId(appId)
    return name
  }

  function tooltipNeeded(root, kind, hasWindows, hasStateHint, shortened) {
    var shown = !!root && DockLabels.labelVisible(root.labelMode, root.labelKind, kind)
    return DockLabels.tooltipNeeded(shown, hasWindows, hasStateHint, shortened)
  }

  function extraBefore(root, slot) {
    return root ? DockLabels.extrasBefore(root.labelExtras, slot) : 0
  }

  function setExtra(root, slot, owner, width) {
    if (!root || slot < 0) return
    var next = DockLabels.withExtra(root.labelExtras, slot, owner, width)
    if (next !== root.labelExtras) root.labelExtras = next
  }

  // Hover-mode label widths, which the card leaves out of its centring.
  function hoverExtra(root) {
    return (root && root.labelMode === "hover") ? DockLabels.extrasTotal(root.labelExtras) : 0
  }

  function setName(root, appId, name) {
    root.labelNames = DockLabels.withLabelName(root.labelNames, appId, name)
    root.saveConfig()
  }

  function openRename(root, appId) {
    root.labelEditAppId = appId
    root.settingsPanelPage = "labels"
    root.openSettingsPanel()
  }

  // Apps the Labels page lists: pinned first, then running, once each.
  function nameRows(root) {
    var rows = []
    var seen = {}
    var lists = [root.dockModel.pinned || [], root.dockModel.running || []]
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var e = lists[l][i]
        if (!e || !e.appId || seen[e.appId]) continue
        seen[e.appId] = true
        var auto = (e.name === "" || e.name === e.appId) ? DockLabels.prettyAppId(e.appId) : e.name
        rows.push({ appId: e.appId, name: root.labelNames[e.appId] || "", auto: auto })
      }
    }
    return rows
  }
}
```

- [ ] **Step 6: Home centres** — `components/logic/DockStyleLogic.qml` `slotHomeCenter`: add one term before `+ root.iconSlot / 2`:

```js
      + root.labelExtraBefore(slotsBefore)
```

- [ ] **Step 7: Keep the old visuals compiling until Task 4** — in `components/DockLabel.qml` the old `style.above` / `style.height` / `style.pill` are gone; change its `visible:` to `false` for now (one line) so nothing renders. In `components/DockCard.qml` remove the label band: line ~315 becomes `height: row.implicitHeight + contentTopInset + contentBottomInset` (drop the three comment lines above it that describe the band) and the Row's `y:` becomes `y: dockCard.contentTopInset` (drop the comment line above it).

- [ ] **Step 8: Verify**

Run **CHECKS** — PASS (structure-check must show `Dock.qml` ≤ 2438).
Run `bash tests/smoke-test.sh --restart` — PASS. The dock looks exactly like with labels off. `python3 -c "import json;print({k:v for k,v in json.load(open('$HOME/.config/omarchy/omadock.json')).items() if k.startswith('label') or k=='showLabels'})"` still shows the old keys (nothing saved yet).

- [ ] **Step 9: Commit**

```bash
git add Dock.qml DockModel.js components/logic/DockConfigLogic.qml components/logic/DockLabelLogic.qml components/logic/DockStyleLogic.qml components/DockLabel.qml components/DockCard.qml tests/unit/dockmodel.test.mjs
git commit -m "feat(labels): side-label settings, migration and width registry

labelMode replaces showLabels/labelPlacement, labelContrast splits into
colour and background; the old keys are read once and dropped on save.
Label looks join the preset keys. The dock root gains a per-slot label
width registry that slotHomeCenter adds, so zoom/wave keep their centres
once tiles grow by a label. The below/above band is removed; the label
visual is disabled until it is rebuilt beside the icon."
```

---

### Task 3: Card anchor and drag targets

**Files:**
- Modify: `components/DockCard.qml` (`x:` ~90-95, import, `labelSlot` at the four tile call sites)
- Modify: `components/logic/DockDragLogic.qml:30`, `:74-85`, `:113-121`

**Interfaces:**
- Consumes: `DockLabels.anchoredX`, `DockLabels.iconCentre`, `root.labelHoverExtra`, `root.alignment`.
- Produces: every tile delegate gets `labelSlot` (int); tiles must expose `labelExtra` (real) — added in Task 4 (until then `it.labelExtra` is `undefined` and treated as 0).

- [ ] **Step 1: Import + anchor** — in `components/DockCard.qml` add `import "../DockLabels.js" as DockLabels` after the DockModel import, and replace the `x:` binding:

```qml
  // Hover-mode labels grow the dock away from its leading edge, so the icon
  // under the pointer stays put (DockLabels.anchoredX).
  x: parent ? DockLabels.anchoredX(parent.width, width, Style.gapsOut * 2,
    root ? root.alignment : "center", root ? root.labelHoverExtra : 0) : 0
```

- [ ] **Step 2: Slots** — add `labelSlot:` next to each `homeCenter:` (the value is that call's `slotsBefore` argument):
  - pinned app (`appSlotComp`, by `homeCenter: rowSlot.home`): `labelSlot: root ? root.appsSlots + rowSlot.index : -1`
  - group (`groupSlotComp`): `labelSlot: root ? root.appsSlots + rowSlot.index : -1`
  - running app: `labelSlot: root ? root.appsSlots + root.pinnedSection.length + root.groupSlots + visibleIdx : -1`
  - folder: `labelSlot: root ? root.appsSlots + root.pinnedSection.length + root.groupSlots + root.visibleRunningCount + index : -1`

  The three tile types get `property int labelSlot: -1` in Task 4; add those three declarations now (one line each, next to `homeCenter`) so this task loads.

- [ ] **Step 3: Drag logic** — `components/logic/DockDragLogic.qml`: add `import "../../DockLabels.js" as DockLabels`. Then:

  `folderInsertIndex` line 30:
```js
      var iconCenter = DockLabels.iconCentre(it.x + (it.gapWidth || 0), it.width - (it.gapWidth || 0), it.labelExtra || 0, root ? root.alignment === "right" : false)
```
  In `handleDragMoved`, replace `var centre = slot.x + slot.width / 2` and the two `slot.width *` tolerances:
```js
      var extra = it.labelExtra || 0
      var centre = DockLabels.iconCentre(slot.x, slot.width, extra, root.alignment === "right")
      var span = slot.width - extra
```
  and use `span * 0.45` / `span * 0.38` where it said `slot.width * 0.45` / `slot.width * 0.38`.

  `rowInsertIndex`:
```js
      var slot = card.pinnedRowRepeater.itemAt(i)
      var it = slot ? slot.item : null
      var extra = it ? (it.labelExtra || 0) : 0
      if (slot && rx < DockLabels.iconCentre(slot.x, slot.width, extra, root ? root.alignment === "right" : false)) return i
```

- [ ] **Step 4: Verify**

Run **CHECKS** — PASS. `node --test tests/unit/labels.test.mjs` already pins `anchoredX` and `iconCentre`. `bash tests/smoke-test.sh` — PASS; with labels off the dock is centred exactly as before (screenshot `grim -o DP-1` crop around y 2010-2160, compare with a capture taken on `priard`).

- [ ] **Step 5: Commit**

```bash
git add components/DockCard.qml components/logic/DockDragLogic.qml components/DockItem.qml components/DockAppGroupItem.qml components/DockFolderItem.qml
git commit -m "feat(labels): anchor the card and aim drags at icons

A centred card now centres on its width without hover-mode label widths,
so a label opening on hover grows the dock to the right instead of
sliding the hovered icon out from under the pointer. Drag insert and
merge targets use the icon centre and icon span, not the middle of a
tile that may carry a label."
```

---

### Task 4: `DockLabel` beside the icon (always mode, looks)

**Files:**
- Modify: `components/DockLabel.qml` (rewrite)
- Create: `fonts/Silkscreen-Regular.ttf`, `fonts/OFL.txt`
- Modify: `components/DockItem.qml`, `components/DockAppGroupItem.qml`, `components/DockFolderItem.qml`
- Modify: `README.md` (font licence line)

**Interfaces:**
- Consumes: root `labelStyle`, `labelName`, `setLabelExtra`, `labelsOpen`, `dragAppId`, `hoverEffect`, `baseIconArt`, `iconArtBottom`, `effectiveCardRadius`; `DockLabels.shortenName`, `revealFrame`.
- Produces on `DockLabel`: inputs `rootRef, kind, appId, name, hovered, iconBox (Item), slot (int)`; outputs `extra` (real), `shortened` (bool), `shown` (bool), `mirror` (bool).
- Produces on each tile: `labelSlot` (int, from Task 3), `labelExtra` (real), `iconCenterX` (real, tile-local).

- [ ] **Step 1: Font** —

```bash
mkdir -p fonts
curl -fsSL -o fonts/Silkscreen-Regular.ttf https://github.com/google/fonts/raw/main/ofl/silkscreen/Silkscreen-Regular.ttf
curl -fsSL -o fonts/OFL.txt https://github.com/google/fonts/raw/main/ofl/silkscreen/OFL.txt
fc-scan --format "%{family}\n" fonts/Silkscreen-Regular.ttf
```
Expected: `Silkscreen`. Check `head -3 fonts/OFL.txt` names the Silkscreen authors.

- [ ] **Step 2: Rewrite `components/DockLabel.qml`**:

```qml
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "../DockLabels.js" as DockLabels

// The name beside a dock tile's icon (apps, app groups, folders). Policy
// comes from root.labelStyle() (DockLabelLogic); this item shortens the name
// to the max width in its own font, animates the reveal, and reports the
// width it adds to the tile (extra) to the dock's registry, which feeds the
// zoom/wave centres and the card's hover anchor. No input handling: hover,
// drag and clicks belong to the tile.
Item {
  id: label

  property var rootRef: null
  readonly property var root: rootRef
  property string kind: "app"
  property string appId: ""
  property string name: ""
  property bool hovered: false
  property Item iconBox: null
  property int slot: -1

  readonly property var style: root ? root.labelStyle(label.kind) : null
  readonly property string fullText: root ? root.labelName(label.appId, label.name) : label.name
  readonly property bool shown: !!label.style && label.style.show && label.fullText !== ""
  readonly property bool mirror: !!label.style && label.style.mirror

  // ---- text and width
  property string shortText: ""
  property bool shortened: false
  readonly property real pad: (label.style && label.style.background === "pill") ? Style.space(6) : Style.space(2)
  readonly property real gap: Style.space(4)
  readonly property real naturalWidth: label.shown && label.shortText !== ""
    ? Math.ceil(textWidth.advanceWidth) + label.pad * 2 + label.gap : 0

  FontLoader {
    source: (label.style && label.style.family === "Silkscreen") ? Qt.resolvedUrl("../fonts/Silkscreen-Regular.ttf") : ""
  }
  TextMetrics { id: probe; font: textItem.font }
  TextMetrics { id: textWidth; font: textItem.font; text: label.shortText }

  function reshorten() {
    if (!label.style) return
    var limit = label.style.maxWidth - label.pad * 2 - label.gap
    var r = DockLabels.shortenName(label.fullText, function(t) { probe.text = t; return probe.advanceWidth <= limit })
    label.shortText = r.text
    label.shortened = r.shortened
  }
  onFullTextChanged: Qt.callLater(label.reshorten)
  onStyleChanged: Qt.callLater(label.reshorten)

  // ---- open state (hover mode arrives in Task 5; always mode is open)
  readonly property bool wantOpen: label.shown && !label.style.hover
  property real progress: label.wantOpen ? 1 : 0
  Behavior on progress { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  readonly property real extra: Math.round(label.progress * label.naturalWidth)

  // ---- width registry
  readonly property string owner: String(label)
  property int _slot: -1
  function syncExtra() {
    if (!label.root) return
    if (label._slot >= 0 && label._slot !== label.slot) label.root.setLabelExtra(label._slot, label.owner, 0)
    label._slot = label.slot
    if (label.slot >= 0) label.root.setLabelExtra(label.slot, label.owner, label.extra)
  }
  onExtraChanged: label.syncExtra()
  onSlotChanged: label.syncExtra()
  Component.onCompleted: { label.reshorten(); label.syncExtra() }
  Component.onDestruction: if (label.root && label._slot >= 0) label.root.setLabelExtra(label._slot, label.owner, 0)

  // ---- reveal (typewriter / scramble swap the text; slide just grows)
  property real revealT: 1
  property string revealStyle: "slide"
  property real seed: 0
  readonly property string drawnText: DockLabels.revealFrame(label.shortText, label.revealStyle, label.revealT, label.seed)
  NumberAnimation {
    id: revealAnim
    target: label; property: "revealT"; from: 0; to: 1
    duration: Math.min(300, 25 * Math.max(1, label.shortText.length))
  }
  function reveal(styleName) {
    label.revealStyle = styleName
    label.seed = Math.random() * 100
    revealAnim.restart()
  }
  onWantOpenChanged: if (label.wantOpen && label.style) label.reveal(label.style.reveal)
  onShortTextChanged: if (label.wantOpen && label.style && label.revealT >= 1 && !revealAnim.running) label.reveal(label.style.reveal)

  // ---- hover sync with the icon's HoverFx
  property real hoverLevel: label.hovered ? 1 : 0
  Behavior on hoverLevel { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  readonly property string hoverEffect: label.root ? label.root.hoverEffect : ""
  readonly property real liftY: label.hoverEffect === "lift" && label.root ? -label.root.baseIconArt * 0.16 * label.hoverLevel : 0
  onHoveredChanged: if (label.hovered && label.hoverEffect === "glitch" && label.progress > 0.5) label.reveal("scramble")
  readonly property real glowLevel: !label.style ? 0
    : Math.max(label.style.effect === "glow" ? 0.55 + 0.45 * label.hoverLevel : 0,
               label.hoverEffect === "glow" ? label.hoverLevel : 0)

  // ---- geometry: beside the icon, the whole tile height
  x: label.mirror ? 0 : (label.iconBox ? label.iconBox.x + label.iconBox.width : 0)
  width: label.extra
  height: parent ? parent.height : 0
  visible: label.extra > 0

  // Plate: one rounded surface behind icon and name.
  Rectangle {
    visible: !!label.style && label.style.background === "plate"
    readonly property real iconW: label.iconBox ? label.iconBox.width : 0
    x: label.mirror ? 0 : -iconW
    width: label.width + iconW
    height: label.iconBox ? label.iconBox.height - Style.space(4) : 0
    anchors.verticalCenter: parent.verticalCenter
    radius: Math.min(height / 2, label.root ? label.root.effectiveCardRadius : Style.cornerRadius)
    color: Util.alpha(label.style ? label.style.ink : Color.bar.text, 0.10 + 0.08 * label.hoverLevel)
    opacity: label.progress
  }

  Item {
    anchors.fill: parent
    clip: label.progress < 0.999

    Item {
      id: content
      x: label.mirror ? 0 : label.gap
      width: Math.max(0, label.naturalWidth - label.gap)
      height: textItem.implicitHeight + Style.space(2)
      // Centred on the icon art, which sits on the dock floor.
      y: label.root ? Math.round(label.height - label.root.iconArtBottom - label.root.baseIconArt / 2 - height / 2) : 0
      opacity: label.progress
      transform: Translate { y: label.liftY }

      Rectangle {
        visible: !!label.style && label.style.background === "pill"
        anchors.fill: parent
        radius: height / 2
        color: Util.alpha(Color.bar.background, 0.85)
      }

      Text {
        id: textItem
        anchors.fill: parent
        anchors.leftMargin: label.pad
        anchors.rightMargin: label.pad
        text: label.drawnText
        textFormat: Text.PlainText
        color: label.style ? label.style.ink : Color.bar.text
        font.family: label.style ? label.style.family : Style.font.family
        font.pixelSize: label.style ? label.style.fontPx : Style.font.caption
        horizontalAlignment: label.mirror ? Text.AlignRight : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        maximumLineCount: 1
        style: (label.style && label.style.effect === "shadow") ? Text.Outline : Text.Normal
        styleColor: Util.alpha("#000000", 0.55)
        layer.enabled: label.glowLevel > 0.01
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: Color.accent
          shadowBlur: 0.6
          shadowHorizontalOffset: 0
          shadowVerticalOffset: 0
          shadowOpacity: label.glowLevel
          autoPaddingEnabled: true
        }
      }
    }
  }
}
```

- [ ] **Step 3: `DockItem.qml`** —
  - `width:` becomes
    ```qml
    width: (root ? (root.iconSlot * (root.waveHover ? item.magnifyScale : 1)) : 0) + item.labelExtra
    ```
  - add next to `homeCenter`/`labelSlot`:
    ```qml
    readonly property real labelExtra: label.extra
    readonly property real iconCenterX: iconBox.x + iconBox.width / 2
    ```
  - `iconBox`: replace `anchors.fill: parent` with
    ```qml
    x: label.mirror ? item.labelExtra : 0
    width: item.width - item.labelExtra
    height: parent.height
    ```
  - both `DockIndicator` and `DockIndicatorRow`: `anchors.horizontalCenter: iconBox.horizontalCenter`
  - replace the old `DockLabel { … tile: item }` block (and its comment) with
    ```qml
    // Name beside the icon (DockLabel, policy in DockLabelLogic).
    DockLabel {
      id: label
      z: -1
      rootRef: item.rootRef
      kind: "app"
      appId: item.appId
      name: item.name
      hovered: area.containsMouse && !item.isDragging
      iconBox: iconBox
      slot: item.visible ? item.labelSlot : -1
    }
    ```

- [ ] **Step 4: `DockAppGroupItem.qml`** —
  - `width:` gets `+ gitem.labelExtra` at the end
  - add `readonly property real labelExtra: label.extra` and `readonly property real iconCenterX: iconSlot.x + iconSlot.width / 2`
  - `iconSlot` (the `Item { id: iconSlot … }`): replace `anchors.horizontalCenter: parent.horizontalCenter` with
    ```qml
    x: (label.mirror ? gitem.labelExtra : 0) + Math.round((gitem.width - gitem.labelExtra - width) / 2)
    ```
  - `indicatorBand`: `anchors.horizontalCenter: iconSlot.horizontalCenter`
  - replace the old `DockLabel` block with
    ```qml
    DockLabel {
      id: label
      z: -1
      rootRef: gitem.rootRef
      kind: "group"
      name: gitem.groupName
      hovered: groupArea.containsMouse
      iconBox: iconSlot
      slot: gitem.labelSlot
    }
    ```

- [ ] **Step 5: `DockFolderItem.qml`** —
  - `width:` becomes `(root ? (root.iconSlot * (root.waveHover ? fitem.magnifyScale : 1)) : 0) + fitem.gapWidth + fitem.labelExtra`
  - add `readonly property real labelExtra: label.extra` and `readonly property real iconCenterX: iconSlot.x + iconSlot.width / 2`
  - `iconSlot.x` becomes
    ```qml
    x: fitem.gapWidth + (label.mirror ? fitem.labelExtra : 0) + Math.round((fitem.width - fitem.gapWidth - fitem.labelExtra - width) / 2)
    ```
  - replace the old `DockLabel` block with
    ```qml
    DockLabel {
      id: label
      z: -1
      rootRef: fitem.rootRef
      kind: "folder"
      name: fitem.name
      hovered: area.containsMouse
      iconBox: iconSlot
      slot: fitem.labelSlot
    }
    ```

- [ ] **Step 6: README** — in the section that lists bundled assets or licences (or at the end of the features section if there is none), add:
  ```markdown
  The pixel label font is [Silkscreen](https://fonts.google.com/specimen/Silkscreen) by Jason Kottke, SIL Open Font License 1.1 (`fonts/OFL.txt`).
  ```

- [ ] **Step 7: Verify**

Run **CHECKS** — PASS; `bash tests/smoke-test.sh --restart` — PASS.
Live screenshots (back up `~/.config/omarchy/omadock.json`, edit with Python, `sleep 1.5`, `grim -o DP-1`, crop `magick X.png -crop 4000x260+1840+1900`, restore the backup):
  1. `labelMode: "always"`, theme font, no background: names right of icons, no overlap, short names; "org.omar…" now reads "Terminal" (or its desktop name).
  2. same with `labelBackground: "pill"` and `"plate"`.
  3. `labelFont: "pixel"`, sizes small/large: crisp, no clipping.
  4. `labelEffect: "glow"` and `"shadow"`.
  5. `alignment: "right"`: labels on the left of icons.
  6. `labelMode: "off"`: identical to the Task 3 capture.
  Look at each image (Read tool) before going on.

- [ ] **Step 8: Commit**

```bash
git add components/DockLabel.qml components/DockItem.qml components/DockAppGroupItem.qml components/DockFolderItem.qml fonts README.md
git commit -m "feat(labels): draw names beside the icon

The label sits to the right of the icon (left on a right-aligned dock),
widens its tile by the shortened name, and registers that width with
the dock. Names shorten in their real font: clean, whole words, then an
ellipsis. Looks: theme/sans/pixel font (bundled Silkscreen, OFL), pill
or plate background, accent glow or outline, typewriter/scramble
reveals, and lift/glitch/glow follow the icon's hover effect."
```

---

### Task 5: Hover mode

**Files:**
- Modify: `components/DockLabel.qml`

**Interfaces:**
- Consumes: `root.labelsOpen`, `root.dragAppId`, style `hover`.
- Produces: hover-mode `wantOpen`; `root.labelsOpen` counts labels with `progress > 0.02` in hover mode.

- [ ] **Step 1: Replace the `wantOpen` line** in `DockLabel.qml` with:

```qml
  // Hover mode opens after a short dwell so a sweep across the dock does
  // not ripple; with another label still open or closing it switches at once.
  property bool dwelled: false
  readonly property bool dragFree: label.root ? label.root.dragAppId === "" : true
  readonly property bool wantOpen: label.shown
    && (!label.style.hover || (label.hovered && label.dwelled && label.dragFree))
  Timer {
    id: dwell
    interval: (label.root && label.root.labelsOpen > 0) ? 1 : 150
    onTriggered: label.dwelled = true
  }
  onHoveredChanged: {
    if (label.hovered) dwell.restart()
    else { dwell.stop(); label.dwelled = false }
  }

  // Counted while open or closing, so the next icon skips the dwell.
  readonly property bool counts: !!label.style && label.style.hover && label.progress > 0.02
  property bool counted: false
  onCountsChanged: {
    if (!label.root || label.counts === label.counted) return
    label.root.labelsOpen += label.counts ? 1 : -1
    label.counted = label.counts
  }
```

  Fold the glitch handler into the new `onHoveredChanged` (QML allows one handler per signal):

```qml
  onHoveredChanged: {
    if (label.hovered) dwell.restart()
    else { dwell.stop(); label.dwelled = false }
    if (label.hovered && label.hoverEffect === "glitch" && label.progress > 0.5) label.reveal("scramble")
  }
```

  and delete the separate glitch `onHoveredChanged` line from Task 4. Extend `Component.onDestruction`:

```qml
  Component.onDestruction: {
    if (label.root && label._slot >= 0) label.root.setLabelExtra(label._slot, label.owner, 0)
    if (label.root && label.counted) label.root.labelsOpen -= 1
  }
```

  Typewriter erase on close: add

```qml
  NumberAnimation { id: eraseAnim; target: label; property: "revealT"; to: 0; duration: 160 }
  onWantOpenChanged: {
    if (!label.style) return
    if (label.wantOpen) label.reveal(label.style.reveal)
    else if (label.style.reveal === "typewriter") { revealAnim.stop(); label.revealStyle = "typewriter"; eraseAnim.restart() }
  }
```

  replacing the Task 4 `onWantOpenChanged` line.

- [ ] **Step 2: Temporary debug IPC** — to capture a hover state without a pointer, the pointer may be moved instead (allowed): `hyprctl dispatch 'hl.dsp.cursor.move({x=X, y=Y})'` with logical coordinates (dock icons around y ≈ 1390, x from the crop / 1.5). Enter from y 1250 first so hover-enter fires. Save the old position with `hyprctl cursorpos` and restore it afterwards.

- [ ] **Step 3: Verify**

Run **CHECKS** — PASS; `bash tests/smoke-test.sh` — PASS.
Live with `labelMode: "hover"`: capture at rest (dock as with labels off), pointer on an icon after 400 ms (label open, hovered icon at the same screen x as at rest — compare the two crops), pointer moved to the next icon (switches without the dwell), pointer out (collapses, dock back to centre). With `hoverEffect` lift / glow / glitch / zoom / wave check one capture each. `journalctl` clean (no binding-loop warnings for `labelExtras`, `x`, `width`).

- [ ] **Step 4: Commit**

```bash
git add components/DockLabel.qml
git commit -m "feat(labels): reveal names on hover

In hover mode a label opens after a 150 ms dwell, or at once while
another label is still open or closing, and never during a drag. The
open count lives on the dock so moving along the icons switches labels
without waiting; typewriter labels erase as they close."
```

---

### Task 6: Tooltip rules

**Files:**
- Modify: `components/DockItem.qml` (`itemTooltip.wanted`)
- Modify: `components/DockAppGroupItem.qml`, `components/DockFolderItem.qml` (`HoverTooltip.blocked`, `target`)
- Modify: `components/HoverTooltip.qml` (`target` property)

**Interfaces:**
- Consumes: `root.labelTooltipNeeded(kind, hasWindows, hasStateHint, shortened)`, `label.shortened`.

- [ ] **Step 1: App tooltip** — `itemTooltip.wanted` gets one more conjunct:

```qml
    readonly property bool wanted: area.containsMouse && !item.isDragging
      && item.name !== "" && (root ? (root.showTooltips && root.contextAppId === "") : true)
      && (root ? root.labelTooltipNeeded("app", item.tooltipWindows.length > 0, item.tooltipText !== item.name, label.shortened) : true)
```

- [ ] **Step 2: Group and folder tooltips** — append to `blocked:`
  - group: `|| (root && !root.labelTooltipNeeded("group", gitem.tooltipWindows.length > 0, false, label.shortened))`
  - folder: `|| (root && !root.labelTooltipNeeded("folder", false, false, label.shortened))`

- [ ] **Step 3: Aim tooltips and the context menu at the icon, not the wide tile**
  - `DockItem.qml` `TooltipWindow { target: item … }` → `target: iconBox`.
  - `DockItem.qml` right-click (~line 451): `item.mapToItem(targetWin, item.width / 2, 0)` → `item.mapToItem(targetWin, item.iconCenterX, 0)` and the fallback `(item.width / 2)` → `item.iconCenterX`.
  - `components/HoverTooltip.qml`: add `property Item target: bubble.parent` next to the other properties and change line 68 `target: bubble.parent` → `target: bubble.target`.
  - `DockAppGroupItem.qml` / `DockFolderItem.qml`: set `target: iconSlot` on their `HoverTooltip`. Also check their right-click handlers for `width / 2` map points and use `iconCenterX` the same way.

- [ ] **Step 4: Verify** — `node --test tests/unit/labels.test.mjs` (tooltipNeeded table) PASS; **CHECKS** PASS. Live with `labelMode: "always"`: hover a pinned app that is not running → no tooltip after 1 s; a running app → tooltip with previews, centred over the icon (not the label); a shortened name (set `labelMaxWidth: 80`) → tooltip with the full name; `labelMode: "off"` → tooltips as before. In hover mode the tooltip appears over the icon after the label has opened and does not move.

- [ ] **Step 5: Commit**

```bash
git add components/DockItem.qml components/DockAppGroupItem.qml components/DockFolderItem.qml components/HoverTooltip.qml
git commit -m "feat(labels): skip tooltips that only repeat the label

With a label shown, an item's tooltip appears only when it adds
something: window previews, a starting/minimized/workspace hint, or the
full name of a shortened label. Tooltips and the context menu aim at
the icon, not the middle of a tile that carries a label."
```

---

### Task 7: Labels settings page, search, rename

**Files:**
- Create: `components/settings/SettingsLabels.qml`
- Modify: `components/settings/SettingsAppearance.qml` (remove the label block, ~347-410)
- Modify: `components/SettingsPanel.qml` (pages list + page instance)
- Modify: `SettingsSearch.js:90-94`
- Modify: `components/DockContextMenu.qml` (row after "Pin to Dock"/"Unpin from Dock" in the app menu ~684)
- Test: `tests/unit/dockmodel.test.mjs` (search)

**Interfaces:**
- Consumes: root `setOption`, `labelNameRows()`, `setLabelName`, `openLabelRename`, `labelEditAppId`; `DockLabels.LABEL_MAX_WIDTH_MIN/MAX`, `MAX_LABEL_NAME`.

- [ ] **Step 1: Failing search test** — append to `tests/unit/dockmodel.test.mjs` (inspect `SettingsSearch.js` for the exported search function name first, e.g. `searchSettings(query)`; use it):

```js
test("settings search finds the labels page", () => {
  const hits = plain(M.searchSettings("typewriter"))
  assert.ok(hits.some((h) => h.key === "labelReveal" && h.page === "labels"))
  assert.ok(!plain(M.searchSettings("label placement")).some((h) => h.key === "labelPlacement"))
})
```
Run: `node --test tests/unit/dockmodel.test.mjs` — FAIL.

- [ ] **Step 2: Search entries** — replace `SettingsSearch.js` lines 90-94 with:

```js
  { key: "labelMode", page: "labels", label: "Labels", terms: ["names", "text", "titles", "beside", "hover", "always"] },
  { key: "labelKind", page: "labels", label: "Show on", terms: ["labels", "apps", "groups", "folders", "which"] },
  { key: "labelFont", page: "labels", label: "Font", terms: ["labels", "pixel", "sans", "typeface", "retro"] },
  { key: "labelSize", page: "labels", label: "Size", terms: ["labels", "font", "small", "large"] },
  { key: "labelColor", page: "labels", label: "Color", terms: ["labels", "colour", "accent", "contrast", "readable"] },
  { key: "labelBackground", page: "labels", label: "Background", terms: ["labels", "pill", "plate", "button"] },
  { key: "labelReveal", page: "labels", label: "Reveal", terms: ["labels", "animation", "typewriter", "scramble", "slide"] },
  { key: "labelEffect", page: "labels", label: "Effect", terms: ["labels", "glow", "shadow", "outline"] },
  { key: "labelMaxWidth", page: "labels", label: "Max width", terms: ["labels", "truncate", "shorten", "long names"] },
  { key: "labelNames", page: "labels", label: "Names", terms: ["labels", "rename", "custom", "shorter"] },
```
Run the test — PASS.

- [ ] **Step 3: Page** — `components/settings/SettingsLabels.qml`:

```qml
import QtQuick
import qs.Commons
import qs.Ui
import "../../DockLabels.js" as DockLabels

// Settings page: name labels beside the dock icons — when they show, how
// they look, and per-app names. Instantiated by SettingsPanel, which injects
// root (the Dock) and panel.

Column {
  id: labelsPage
  property var root: null
  property var panel: null
  width: parent.width

  SectionLabel { text: "Labels" }

  ChoiceRow {
    key: "labelMode"
    label: "Labels"
    hint: "Names beside the icons: always, or slid out while the pointer rests on an icon."
    options: [
      { value: "off", label: "Off" },
      { value: "always", label: "Always" },
      { value: "hover", label: "On hover" }
    ]
    value: root ? root.labelMode : "off"
    onPicked: function(v) { root.setOption("labelMode", v) }
  }

  Column {
    width: parent.width
    visible: root ? root.labelMode !== "off" : false

    ChoiceRow {
      key: "labelKind"
      label: "Show on"
      options: [
        { value: "all", label: "All" },
        { value: "apps", label: "Apps" },
        { value: "groups", label: "App groups" },
        { value: "folders", label: "Folders" }
      ]
      value: root ? root.labelKind : "all"
      onPicked: function(v) { root.setOption("labelKind", v) }
    }

    SectionLabel { text: "Look" }

    ChoiceRow {
      key: "labelFont"
      label: "Font"
      options: [
        { value: "theme", label: "Theme" },
        { value: "sans", label: "Sans" },
        { value: "pixel", label: "Pixel" }
      ]
      value: root ? root.labelFont : "theme"
      onPicked: function(v) { root.setOption("labelFont", v) }
    }
    ChoiceRow {
      key: "labelSize"
      label: "Size"
      options: [
        { value: "small", label: "Small" },
        { value: "medium", label: "Medium" },
        { value: "large", label: "Large" }
      ]
      value: root ? root.labelSize : "small"
      onPicked: function(v) { root.setOption("labelSize", v) }
    }
    ChoiceRow {
      key: "labelColor"
      label: "Color"
      hint: "High picks black or white for the dock background."
      options: [
        { value: "theme", label: "Theme" },
        { value: "high", label: "High contrast" },
        { value: "accent", label: "Accent" }
      ]
      value: root ? root.labelColor : "theme"
      onPicked: function(v) { root.setOption("labelColor", v) }
    }
    ChoiceRow {
      key: "labelBackground"
      label: "Background"
      hint: "Plate puts icon and name on one surface, like a button."
      options: [
        { value: "none", label: "None" },
        { value: "pill", label: "Pill" },
        { value: "plate", label: "Plate" }
      ]
      value: root ? root.labelBackground : "none"
      onPicked: function(v) { root.setOption("labelBackground", v) }
    }
    ChoiceRow {
      key: "labelReveal"
      label: "Reveal"
      options: [
        { value: "slide", label: "Slide" },
        { value: "typewriter", label: "Typewriter" },
        { value: "scramble", label: "Scramble" }
      ]
      value: root ? root.labelReveal : "slide"
      onPicked: function(v) { root.setOption("labelReveal", v) }
    }
    ChoiceRow {
      key: "labelEffect"
      label: "Effect"
      options: [
        { value: "none", label: "None" },
        { value: "glow", label: "Accent glow" },
        { value: "shadow", label: "Outline" }
      ]
      value: root ? root.labelEffect : "none"
      onPicked: function(v) { root.setOption("labelEffect", v) }
    }
    SliderRow {
      key: "labelMaxWidth"
      label: "Max width"
      hint: "Longer names drop subtitles, then trailing words, then end in an ellipsis."
      minimum: DockLabels.LABEL_MAX_WIDTH_MIN
      maximum: DockLabels.LABEL_MAX_WIDTH_MAX
      step: 10
      suffix: " px"
      value: root ? root.labelMaxWidth : 140
      onCommitted: function(v) { root.setOption("labelMaxWidth", Math.round(v)) }
    }

    SectionLabel { text: "Names"; visible: root ? root.labelKind === "all" || root.labelKind === "apps" : false }

    Repeater {
      model: (root && (root.labelKind === "all" || root.labelKind === "apps")) ? root.labelNameRows() : []
      delegate: Item {
        id: nameRow
        required property var modelData
        width: labelsPage.width
        implicitHeight: Style.space(44)

        // The context menu's "Rename Label…" lands here with this app.
        readonly property bool wanted: !!labelsPage.root && labelsPage.visible
          && labelsPage.root.labelEditAppId === nameRow.modelData.appId
        onWantedChanged: if (nameRow.wanted) Qt.callLater(function() {
          nameField.forceActiveFocus()
          nameField.selectAll()
          labelsPage.root.labelEditAppId = ""
        })

        Text {
          anchors.left: parent.left
          anchors.right: nameField.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: nameRow.modelData.auto
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        TextField {
          id: nameField
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(220)
          text: nameRow.modelData.name
          placeholderText: nameRow.modelData.auto
          maximumLength: DockLabels.MAX_LABEL_NAME
          foreground: Color.menu.text
          function commit() {
            if (text !== nameRow.modelData.name) labelsPage.root.setLabelName(nameRow.modelData.appId, text)
          }
          Keys.onReturnPressed: { commit(); labelsPage.panel.refocus() }
          Keys.onEnterPressed: { commit(); labelsPage.panel.refocus() }
          onActiveFocusChanged: if (!activeFocus) commit()
        }
      }
    }
  }
}
```

- [ ] **Step 4: Panel** — `components/SettingsPanel.qml`: in `pages` insert after the appearance entry
```js
    { id: "labels", label: "Labels", glyph: "󰓹" },
```
and after the `SettingsAppearance { … }` instance:
```qml
          SettingsLabels {
            root: panel.root
            panel: panel
            visible: panel.page === "labels"
          }
```
Remove the whole label block from `SettingsAppearance.qml` (the `SwitchRow` with `key: "showLabels"` and the `Column` holding `labelKind`, `labelPlacement`, `labelSize`, `labelContrast`, plus a `SectionLabel` that heads only them, if any).

- [ ] **Step 5: Context menu** — `components/DockContextMenu.qml`: add `import "../DockLabels.js" as DockLabels`; after the app menu's Pin/Unpin `ContextRow` (~line 684-695) add:

```qml
        ContextRow {
          visible: root ? DockLabels.labelVisible(root.labelMode, root.labelKind, "app") : false
          text: "Rename Label…"
          onTriggered: {
            if (!root) return
            var aid = root.contextAppId
            root.closeContext()
            root.openLabelRename(aid)
          }
        }
```
Confirm `wc -l components/DockContextMenu.qml` ≤ 800.

- [ ] **Step 6: Verify** — **CHECKS** PASS; `bash tests/smoke-test.sh --restart` PASS. `omarchy-shell omadock openSettingsPage labels`, screenshot the panel: all rows present, Names list shows pinned + running apps. Edit the config to `"labelNames": {"<a pinned appId>": "Mat"}` → the dock label reads "Mat". `omarchy-shell omadock closeSettings`. Ask the user to try "Rename Label…" from an app's context menu and type a name (keyboard input is never synthesised).

- [ ] **Step 7: Commit**

```bash
git add components/settings/SettingsLabels.qml components/settings/SettingsAppearance.qml components/SettingsPanel.qml SettingsSearch.js components/DockContextMenu.qml tests/unit/dockmodel.test.mjs
git commit -m "feat(labels): Labels settings page and per-app names

Labels get their own page: mode, targets, font, size, colour,
background, reveal, effect, max width, and a list of apps whose label
text can be overridden. The app context menu's Rename Label… opens that
page focused on the app, since the menu window takes no keyboard input."
```

---

### Task 8: Live verification, benchmark, docs, merge to `priard`

**Files:**
- Modify: `README.md` (labels feature text + screenshot `assets/preview-labels.png`)
- On `priard` only: `FORK.md`, `manifest.json` version suffix

- [ ] **Step 1: Full checks** — **CHECKS** PASS; `bash tests/smoke-test.sh --restart` PASS.

- [ ] **Step 2: Benchmark** — read `tests/bench/README.md`; run the idle and hover-sweep scenarios with `labelMode` off, always and hover; compare CPU/VRAM. Expected: always ≈ off at idle; hover sweep within ~10 % of zoom's.

- [ ] **Step 3: Screenshot for README** — `labelMode: "always"`, `labelBackground: "plate"`, theme font; crop the dock, save as `assets/preview-labels.png` (replacing upstream's), update the README labels paragraph to describe: beside the icon, always/on hover, tooltip only when it adds something, looks, rename. Commit:

```bash
git add README.md assets/preview-labels.png
git commit -m "docs(readme): describe side labels"
```

- [ ] **Step 4: User checks** (ask, do not simulate): sweep the pointer across the dock in hover mode (no jumping), drag an app between labelled tiles and onto another app (gap and merge land on icons), rename a label from the context menu, switch presets (label look follows).

- [ ] **Step 5: Merge into `priard`**

```bash
git push fork feat/side-labels
git switch priard
git merge-tree --write-tree priard feat/side-labels   # must not report conflicts
git merge --no-ff feat/side-labels -m "Merge branch 'feat/side-labels' into priard"
```
Bump `manifest.json` to `4.0.3-priard.3`, add a "Fork only / not upstream yet" line to `FORK.md` for side labels, commit (`chore(fork): side labels in priard`), run `bash tests/run-all.sh` (rebaseline qmllint only if the new warnings are reviewed and harmless), `bash tests/smoke-test.sh --restart`, then `git push fork priard` (retry on "remote rejected").

- [ ] **Step 6: Stop.** Do not open an upstream PR; tell the user it is ready when they want one.
