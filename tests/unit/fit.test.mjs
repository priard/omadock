// Tests for DockFit.js, the planner that keeps the dock inside its screen
// (spacing, icons, then "»"). Plain JS, run in a vm context like DockLayout.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const F = vm.createContext({})
vm.runInContext(readFileSync(new URL("../../DockFit.js", import.meta.url), "utf8"), F)
const plain = (v) => JSON.parse(JSON.stringify(v))

function input(over) {
  return Object.assign({
    available: 10000,
    iconSize: 48, floor: 24, slotPad: 10, gapMax: 4, gapMin: 0,
    sepMax: 8, sepMin: 8, tileFactor: 1.5, wave: false, margin: 8,
    items: [
      { id: "button", kind: "button" },
      { id: "pin:a", kind: "app" },
      { id: "pin:b", kind: "app" },
      { id: "sep:1", kind: "separator" },
      { id: "run:c", kind: "app" },
      { id: "sep:2", kind: "separator" },
      { id: "folder:d", kind: "folder" },
      { id: "drive:e", kind: "drive" }
    ]
  }, over || {})
}
// Slots 58 px each (48 + 10): 6 slots = 348, 2 seps = 16, 7 gaps * 4 = 28.
const FULL = 392

test("a row that fits keeps the configured values", () => {
  const p = plain(F.plan(input(), null))
  assert.equal(p.level, 0)
  assert.equal(p.t, 1)
  assert.equal(p.iconSize, 48)
  assert.equal(p.overflowFrom, -1)
  assert.equal(p.width, FULL)
})

test("step 1 tightens spacing", () => {
  // gaps 7*4 = 28 -> at t=0: 364.
  const p = plain(F.plan(input({ available: 380 }), null))
  assert.ok(p.t < 1 && p.t > 0)
  assert.equal(p.iconSize, 48)
  assert.ok(p.width <= 380)
  assert.ok(p.level > 0 && p.level <= 1)
})

test("step 2 shrinks icons down to the floor", () => {
  // t=0: 364 = 6*58 + 16. 350 allows a slot of 55 (6*55+16 = 346): icon 45.
  let p = plain(F.plan(input({ available: 350 }), null))
  assert.equal(p.t, 0)
  assert.equal(p.iconSize, 45)
  p = plain(F.plan(input({ available: 6 * 34 + 16 }), null))
  assert.equal(p.iconSize, 24)
  assert.equal(p.overflowFrom, -1)
})

test("step 3 moves items from the end of the row into overflow", () => {
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

test("the Wave reserve keeps room for the magnification", () => {
  // The reserve (ceil(58 * 0.872) = 51) is part of the width, so the
  // configured row no longer fits in FULL.
  const p = plain(F.plan(input({ wave: true, available: FULL }), null))
  assert.ok(p.level > 0)
  assert.ok(p.width <= FULL)
})

test("hysteresis: a gentler plan needs the margin to come back", () => {
  const tight = plain(F.plan(input({ available: 350 }), null))
  assert.equal(tight.iconSize, 45)
  // 355 would fit icon 46 (6*56+16 = 352) but not with the 8 px margin.
  const held = plain(F.plan(input({ available: 355 }), tight))
  assert.equal(held.iconSize, 45)
  const back = plain(F.plan(input({ available: 400 }), tight))
  assert.equal(back.iconSize, 48)
  assert.equal(back.level, 0)
})

test("tiles are one and a half slots wide", () => {
  const i = input({ items: [{ id: "tile:x", kind: "tile" }, { id: "tile:y", kind: "tile" }] })
  assert.equal(F.rowWidth(i, { t: 1, iconSize: 48, overflowFrom: -1 }), 87 + 87 + 4)
})

test("fixed gaps and width count in every cut (the Both sides gap item)", () => {
  const i = input({ fixedGaps: 1, fixedWidth: 1 })
  assert.equal(F.rowWidth(i, { t: 1, iconSize: 48, overflowFrom: -1 }), FULL + 4 + 1)
  assert.equal(F.rowWidth(i, { t: 1, iconSize: 48, overflowFrom: 0 }), 34 + 24 + 4 + 1)
})

test("rest is the drawn width: no Wave reserve", () => {
  const p = plain(F.plan(input({ wave: true, available: 10000 }), null))
  const slot = p.iconSize + 10
  assert.ok(p.rest < p.width)
  assert.ok(p.width - p.rest >= Math.ceil(slot * 0.4 * 2.18))
})

test("rest is the packed row: the Both sides gap item is not in it", () => {
  const p = plain(F.plan(input({ fixedGaps: 1, fixedWidth: 1 }), null))
  assert.equal(p.width, FULL + 4 + 1)
  assert.equal(p.rest, FULL)
})
