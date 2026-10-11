// Tests for DockFit.js, the planner that keeps the dock inside its screen
// (shorter labels, folded labels, spacing, icons, then "»"). Plain JS, run
// in a vm context like DockLayout.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const F = vm.createContext({})
vm.runInContext(readFileSync(new URL("../../DockFit.js", import.meta.url), "utf8"), F)
const plain = (v) => JSON.parse(JSON.stringify(v))

const lab = (text) => ({ text, inner: 20, outer: 24, folded: 0, asleep: false })
function input(over) {
  return Object.assign({
    available: 10000, labels: true, labelMax: 140, labelMin: 80,
    iconSize: 48, floor: 24, slotPad: 10, gapMax: 4, gapMin: 0,
    sepMax: 8, sepMin: 8, tileFactor: 1.5, wave: false, dpr: 0, margin: 8,
    items: [
      { id: "button", kind: "button", pinned: false, running: false, label: null },
      { id: "pin:a", kind: "app", pinned: true, running: true, label: lab(120) },
      { id: "pin:b", kind: "app", pinned: true, running: false, label: lab(100) },
      { id: "sep:1", kind: "separator" },
      { id: "run:c", kind: "app", pinned: false, running: true, label: lab(60) },
      { id: "sep:2", kind: "separator" },
      { id: "folder:d", kind: "folder", pinned: true, running: false, label: lab(70) },
      { id: "drive:e", kind: "drive", pinned: false, running: false, label: null }
    ]
  }, over || {})
}
// Slots 58 px each (48 + 10), labels: min(text, 140 - 20) + 24.
// a: 120+24=144, b: 100+24=124, c: 60+24=84, d: 70+24=94 -> 446
// 6 slots = 348, 2 seps = 16, 7 gaps * 4 = 28 -> 838
const FULL = 838

test("a row that fits keeps the configured values", () => {
  const p = plain(F.plan(input(), null))
  assert.equal(p.level, 0)
  assert.equal(p.labelMax, 140)
  assert.equal(p.fold, "none")
  assert.equal(p.t, 1)
  assert.equal(p.iconSize, 48)
  assert.equal(p.overflowFrom, -1)
  assert.equal(p.width, FULL)
})

test("step 1 shortens labels to the widest max width that fits", () => {
  // a at L: min(120, L-20)+24. Only a shrinks down to L = 120: 838 - 20 = 818.
  const p = plain(F.plan(input({ available: 818 }), null))
  assert.equal(p.fold, "none")
  assert.equal(p.labelMax, 120)
  assert.ok(p.width <= 818)
  assert.ok(p.level > 0 && p.level < 2)
})

test("step 2 folds closed pinned apps first, then apps, then everything", () => {
  // At L=80 the labels are 84+84+84+84 = 336 -> 728. b folded (closed pinned) saves 84 -> 644.
  let p = plain(F.plan(input({ available: 650 }), null))
  assert.equal(p.fold, "closedPinned")
  // apps folded too: a and c go -> 644 - 168 = 476 (d still labelled).
  p = plain(F.plan(input({ available: 480 }), null))
  assert.equal(p.fold, "apps")
  // everything folded: 476 - 84 = 392.
  p = plain(F.plan(input({ available: 400 }), null))
  assert.equal(p.fold, "all")
  assert.equal(p.t, 1)
})

test("a folded fit still gives the remaining labels the most room", () => {
  // closedPinned with 650 px: 644 at L=80; a and d take the 6 px left (L = 83).
  const p = plain(F.plan(input({ available: 650 }), null))
  assert.equal(p.labelMax, 83)
  assert.ok(p.width <= 650)
})

test("step 3 tightens spacing after every label is folded", () => {
  // all folded at t=1: 392. gaps 7*4 = 28 -> at t=0: 364.
  const p = plain(F.plan(input({ available: 380 }), null))
  assert.equal(p.fold, "all")
  assert.ok(p.t < 1 && p.t > 0)
  assert.equal(p.iconSize, 48)
  assert.ok(p.width <= 380)
})

test("step 4 shrinks icons down to the floor", () => {
  // t=0: 364 = 6*58 + 16. 350 allows a slot of 55 (6*55+16 = 346): icon 45.
  let p = plain(F.plan(input({ available: 350 }), null))
  assert.equal(p.t, 0)
  assert.equal(p.iconSize, 45)
  p = plain(F.plan(input({ available: 6 * 34 + 16 }), null))
  assert.equal(p.iconSize, 24)
  assert.equal(p.overflowFrom, -1)
})

test("step 5 moves items from the end of the row into overflow", () => {
  // floor: slot 34. Full row 6*34+16 = 220. "»" is one more slot (34).
  const p = plain(F.plan(input({ available: 150 }), null))
  assert.equal(p.iconSize, 24)
  assert.ok(p.overflowFrom > 0)
  // The kept part ends on a real item, never on a separator.
  const items = input().items
  assert.notEqual(items[p.overflowFrom - 1].kind, "separator")
  assert.ok(p.width <= 150)
})

test("one item wider than the screen leaves only the overflow tile", () => {
  const p = plain(F.plan(input({ available: 40 }), null))
  assert.equal(p.overflowFrom, 0)
  assert.equal(p.width, 34)
})

test("an empty row keeps the configured values", () => {
  const p = plain(F.plan(input({ items: [], available: 0 }), null))
  assert.equal(p.level, 0)
  assert.equal(p.overflowFrom, -1)
})

test("labels that take no room skip steps 1 and 2", () => {
  const p = plain(F.plan(input({ labels: false, available: 300 }), null))
  assert.equal(p.fold, "none")
  assert.equal(p.labelMax, 140)
  assert.ok(p.iconSize < 48 || p.t < 1)
})

test("an app already asleep (When running) counts as folded", () => {
  const i = input()
  i.items[2].label = Object.assign(lab(100), { asleep: true })
  assert.equal(F.rowWidth(i, { labelMax: 140, fold: "none", t: 1, iconSize: 48, overflowFrom: -1 }), FULL - 124)
})

test("the Wave reserve keeps room for the magnification", () => {
  // The reserve (ceil(58 * 0.872) = 51) is part of the width, so the
  // configured row no longer fits in FULL.
  const p = plain(F.plan(input({ wave: true, available: FULL }), null))
  assert.ok(p.level > 0)
  assert.ok(p.width <= FULL)
})

test("hysteresis: a gentler plan needs the margin to come back", () => {
  const tight = plain(F.plan(input({ available: 650 }), null))
  assert.equal(tight.fold, "closedPinned")
  // 729 would fit at L=80 unfolded (728) but not with the 8 px margin.
  const held = plain(F.plan(input({ available: 729 }), tight))
  assert.equal(held.fold, "closedPinned")
  const back = plain(F.plan(input({ available: 740 }), tight))
  assert.equal(back.fold, "none")
})

test("plate rows snap the slot and the gap to the device grid", () => {
  const p = plain(F.plan(input({ dpr: 1.5, available: 300, gapMin: 4 }), null))
  const slot = p.iconSize + 10
  assert.equal(Math.abs(slot * 1.5 - Math.round(slot * 1.5)) < 1e-9, true)
  assert.equal(Math.abs(p.gap * 1.5 - Math.round(p.gap * 1.5)) < 1e-9, true)
})

test("tiles are one and a half slots wide", () => {
  const i = input({ items: [{ id: "tile:x", kind: "tile" }, { id: "tile:y", kind: "tile" }] })
  assert.equal(F.rowWidth(i, { labelMax: 140, fold: "none", t: 1, iconSize: 48, overflowFrom: -1 }), 87 + 87 + 4)
})
