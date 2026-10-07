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
    labelMode: "off", labelKind: "all", labelFont: "theme", labelSize: "medium",
    labelWeight: "medium", labelColor: "auto", labelBackground: "none", labelShape: "dock",
    labelIndicators: "before", labelReveal: "slide", labelEffect: "none", labelMaxWidth: 140, labelNames: {}
  })
})

test("readLabelConfig migrates upstream's first label keys", () => {
  const c = L.readLabelConfig({ showLabels: true, labelPlacement: "above", labelContrast: "pill", labelSize: "small" })
  assert.equal(c.labelMode, "always")
  assert.equal(c.labelBackground, "pill")
  assert.equal(c.labelColor, "auto")
  // The band's sizes were tuned for a strip under the icons; side labels
  // start from the readable default.
  assert.equal(c.labelSize, "medium")
  assert.equal(L.readLabelConfig({ showLabels: true, labelContrast: "high" }).labelColor, "auto")
  assert.equal(L.readLabelConfig({ showLabels: true, labelContrast: "theme" }).labelColor, "theme")
  assert.equal(L.readLabelConfig({ showLabels: false }).labelMode, "off")
  // New keys win over old ones.
  assert.equal(L.readLabelConfig({ showLabels: true, labelMode: "hover" }).labelMode, "hover")
})

test("readLabelConfig validates values", () => {
  assert.equal(L.readLabelConfig({ labelMode: "always", labelSize: "small" }).labelSize, "small")
  assert.equal(L.readLabelConfig({ labelMode: "always", labelColor: "high" }).labelColor, "auto")
  assert.equal(L.readLabelConfig({ labelMode: "always", labelEffect: "shadow" }).labelEffect, "outline")
  assert.equal(L.readLabelConfig({ labelWeight: "bold", labelShape: "square" }).labelWeight, "bold")
  assert.equal(L.readLabelConfig({ labelShape: "square" }).labelShape, "square")
  assert.equal(L.readLabelConfig({ labelIndicators: "after" }).labelIndicators, "after")
  assert.equal(L.readLabelConfig({ labelIndicators: "sideways" }).labelIndicators, "before")
  assert.equal(L.readLabelConfig({ labelShape: "blob", labelWeight: "heavy" }).labelShape, "dock")
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

test("shortenName never ends a cut on a lone symbol word", () => {
  assert.deepEqual(plain(L.shortenName("Spotifast & more", fitsChars(11))), { text: "Spotifast", shortened: true })
  assert.deepEqual(plain(L.shortenName("Tools + Extras Pack", fitsChars(8))), { text: "Tools", shortened: true })
})

test("labelRadius follows the shape, or the dock's own corner ratio", () => {
  assert.equal(L.labelRadius("pill", 20, 0), 10)
  assert.equal(L.labelRadius("rounded", 20, 0.5), 5)
  assert.equal(L.labelRadius("square", 20, 0.5), 0)
  // A square dock gives square labels, a pill dock pill labels.
  assert.equal(L.labelRadius("dock", 20, 0), 0)
  assert.equal(L.labelRadius("dock", 20, 0.5), 10)
  assert.equal(L.labelRadius("dock", 20, 0.2), 4)
  assert.equal(L.labelRadius("dock", 20, 3), 10)
})

test("homeExtra counts the part of a slot's own extra that sits before its icon", () => {
  let e = {}
  e = L.withExtra(e, 0, "a", 30, 0)
  // Slot 1: 50 wide, 10 of it (a side-indicator column) before the icon.
  e = L.withExtra(e, 1, "b", 50, 10)
  assert.equal(L.homeExtra(e, 1), 40)
  assert.equal(L.homeExtra(e, 1, false), 30)
  assert.equal(L.homeExtra(e, 2), 80)
  // Same width, new split: still an update.
  const e2 = L.withExtra(e, 1, "b", 50, 50)
  assert.notEqual(e2, e)
  assert.equal(L.homeExtra(e2, 1), 80)
})

test("pickLabelLook applies a preset's label look and keeps the rest", () => {
  const cur = { labelFont: "theme", labelSize: "small", labelWeight: "medium", labelColor: "auto",
    labelBackground: "none", labelShape: "dock", labelIndicators: "before", labelReveal: "slide", labelEffect: "none", labelMaxWidth: 140 }
  const out = plain(L.pickLabelLook({ labelFont: "pixel", labelBackground: "plate", labelMaxWidth: 999, labelShape: "blob", iconSize: 40 }, cur))
  assert.deepEqual(out, Object.assign({}, cur, { labelFont: "pixel", labelBackground: "plate", labelMaxWidth: 240 }))
  // A preset saved before label looks existed changes nothing.
  assert.deepEqual(plain(L.pickLabelLook({ iconSize: 40 }, cur)), cur)
  assert.equal(L.pickLabelLook({ labelEffect: "shadow" }, cur).labelEffect, "outline")
  assert.equal(L.pickLabelLook({ labelIndicators: "under" }, cur).labelIndicators, "under")
})

test("nameRowsKey changes only when the listed apps change", () => {
  const a = [{ appId: "zen", auto: "Zen Browser" }, { appId: "t3", auto: "T3 Code" }]
  const b = [{ appId: "zen", auto: "Zen Browser", windowTitle: "x" }, { appId: "t3", auto: "T3 Code" }]
  assert.equal(L.nameRowsKey(a), L.nameRowsKey(b))
  assert.notEqual(L.nameRowsKey(a), L.nameRowsKey(a.slice(0, 1)))
})

test("withFolderName renames one pinned folder, blank restores the directory name", () => {
  const list = [{ path: "/home/u/Downloads", name: "Downloads", icon: "folder-download" }, { path: "~/code/omazen", name: "omazen", icon: "folder" }]
  const a = plain(L.withFolderName(list, "~/code/omazen", "  Zen work  "))
  assert.equal(a[1].name, "Zen work")
  assert.equal(a[1].icon, "folder")
  assert.equal(a[0].name, "Downloads")
  assert.equal(L.withFolderName(list, "~/code/omazen", "   ")[1].name, "omazen")
  assert.equal(L.withFolderName([{ path: "/data/x/", name: "q" }], "/data/x/", "")[0].name, "x")
  assert.equal(L.withFolderName([{ path: "~", name: "q" }], "~", "")[0].name, "Home")
  assert.equal(L.withFolderName(list, "~/code/omazen", "x".repeat(300))[1].name.length, 120)
  assert.equal(L.withFolderName(list, "/nope", "X"), list)
})

test("sideMarks only for an always-on plate with side indicators", () => {
  assert.equal(L.sideMarks("always", "plate", "before"), true)
  assert.equal(L.sideMarks("always", "plate", "after"), true)
  assert.equal(L.sideMarks("always", "plate", "under"), false)
  assert.equal(L.sideMarks("hover", "plate", "before"), false)
  assert.equal(L.sideMarks("always", "pill", "before"), false)
  assert.equal(L.sideMarks("off", "plate", "before"), false)
})
