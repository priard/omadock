// Tests for DockLayout.js, the pure helpers behind the Dock / Panel layouts
// and the alignments. Plain JS with no Qt globals, run in a vm context.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKLAYOUT || new URL("../../DockLayout.js", import.meta.url)
const L = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), L)
const plain = (v) => JSON.parse(JSON.stringify(v))

test("normalizeLayout keeps panel, everything else is dock", () => {
  assert.equal(L.normalizeLayout("panel"), "panel")
  assert.equal(L.normalizeLayout("PANEL"), "panel")
  assert.equal(L.normalizeLayout("dock"), "dock")
  for (const v of ["", null, undefined, "taskbar", 3, {}]) assert.equal(L.normalizeLayout(v), "dock")
})

test("normalizeAlignment accepts the four values, else center", () => {
  for (const v of ["left", "right", "spread", "center"]) assert.equal(L.normalizeAlignment(v), v)
  assert.equal(L.normalizeAlignment("Right"), "right")
  for (const v of ["", null, undefined, "both", "top", 7]) assert.equal(L.normalizeAlignment(v), "center")
})

test("placement: panel ignores split", () => {
  assert.deepEqual(plain(L.placement("panel", "left", true, true)), { panel: true, split: false, align: "left" })
  assert.deepEqual(plain(L.placement("dock", "left", true, true)), { panel: false, split: true, align: "left" })
})

test("placement: spread needs panel or split, and a right group", () => {
  assert.equal(L.placement("dock", "spread", false, true).align, "center")
  assert.equal(L.placement("dock", "spread", true, true).align, "spread")
  assert.equal(L.placement("panel", "spread", false, true).align, "spread")
  assert.equal(L.placement("panel", "spread", false, false).align, "left")
  assert.equal(L.placement("dock", "spread", true, false).align, "left")
  assert.equal(L.placement("bogus", "bogus", "yes", true).align, "center")
  assert.equal(L.placement("bogus", "bogus", "yes", true).split, false)
})

test("spreadAvailable", () => {
  assert.equal(L.spreadAvailable("panel", false), true)
  assert.equal(L.spreadAvailable("dock", true), true)
  assert.equal(L.spreadAvailable("dock", false), false)
})

test("stretchedBox: panel spans the window, dock spread keeps the inset", () => {
  assert.deepEqual(plain(L.stretchedBox({ panel: true, split: false, align: "center" }, 5120, 20)), { x: 0, width: 5120 })
  assert.deepEqual(plain(L.stretchedBox({ panel: false, split: true, align: "spread" }, 5120, 20)), { x: 20, width: 5080 })
  assert.equal(L.stretchedBox({ panel: false, split: false, align: "center" }, 5120, 20), null)
  assert.equal(L.stretchedBox({ panel: false, split: true, align: "left" }, 5120, 20), null)
  assert.deepEqual(plain(L.stretchedBox({ panel: false, split: true, align: "spread" }, 10, 20)), { x: 20, width: 0 })
})

test("rowOffset per alignment, clamped at 0 on overflow", () => {
  assert.equal(L.rowOffset("left", 1000, 400), 0)
  assert.equal(L.rowOffset("right", 1000, 400), 600)
  assert.equal(L.rowOffset("center", 1000, 401), 300)
  assert.equal(L.rowOffset("spread", 1000, 400), 0)
  assert.equal(L.rowOffset("right", 300, 400), 0)
  assert.equal(L.rowOffset("center", 300, 400), 0)
})

test("spreadGap fills what is left between the groups, never negative", () => {
  assert.equal(L.spreadGap(1000, 300, 200, 4), 492)
  assert.equal(L.spreadGap(400, 300, 200, 4), 0)
})

test("spreadHomeShift moves resting right-group centres by the free width", () => {
  assert.equal(L.spreadHomeShift(1000, 600), 400)
  assert.equal(L.spreadHomeShift(500, 600), 0)
})
