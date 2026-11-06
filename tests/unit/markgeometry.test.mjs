// Tests for DockMarkGeometry.js, the one owner of how big a dock mark is and how
// much room it needs. Plain JS with no Qt globals, run in a vm context like
// DockLabels.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMARKGEOMETRY || new URL("../../DockMarkGeometry.js", import.meta.url)
const G = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), G)
const plain = (v) => JSON.parse(JSON.stringify(v))
// Style.space: whole pixels, never below one (shell Commons/Style.qml).
const space = (scale) => (n) => Math.max(1, Math.round(n * scale))

test("snap: a size lands on the pixel grid, never below one", () => {
  assert.equal(G.snap(5, 1), 5)
  assert.equal(G.snap(4, 1), 4)
  assert.equal(G.snap(5, 1.5), 8 / 1.5)   // 7.5 device px rounds to 8
  assert.equal(G.snap(4, 1.5), 4)
  assert.equal(G.snap(5, 2), 5)
  assert.equal(G.snap(4, 3), 4)
  assert.equal(G.snap(0.5, 1), 1)
})

test("cell: as wide as the widest mark, a dot or the bar", () => {
  assert.equal(G.cell(space(1), 1, false), 5)   // 5px dot
  assert.equal(G.cell(space(1), 1, true), 4)    // dense
  assert.equal(G.cell(space(1), 2, false), 5)
  assert.equal(G.cell(space(1.5), 1.5, false), 8)   // a denser theme, at 1.5x
})

test("dot: the mark itself, a hairline at the very least", () => {
  assert.equal(G.dot(space(1), 1, false), 5)
  assert.equal(G.dot(space(1), 1, true), 4)
  assert.equal(G.dot(space(1), 1.5, false), 8 / 1.5)   // 8 device px at 1.5x
  assert.equal(G.dot(space(1), 4, false), 5)
  // A theme too dense to draw a whole pixel still gets 2/dpr.
  assert.equal(G.dot(() => 1, 1, false), 2)
  assert.equal(G.dot(() => 1, 1, true), 2)
})

test("bar: the accent bar's thickness and length", () => {
  assert.equal(G.barThickness(space(1), 1), 4)
  assert.equal(G.barThickness(space(1), 2), 4)
  assert.equal(G.barLength(space(1), 1, false), 12)
  assert.equal(G.barLength(space(1), 1, true), 9)
  assert.equal(G.barLength(space(1), 2, false), 12)
})

test("spacing and the overflow pill", () => {
  assert.equal(G.rowSpacing(space(1), 1, false), 3)
  assert.equal(G.rowSpacing(space(1), 1, true), 2)
  assert.equal(G.rowSpacing(space(1), 2, false), 3)
  assert.equal(G.pillWidth(space(1), 20), 24)
  assert.equal(G.pillHeight(space(1)), 5)
})

test("a mark is never bigger than the cell reserved for it", () => {
  // The hairline floor has one owner and every drawn mark applies it, so the
  // cell - which is the widest of those marks - follows the floor too. It used
  // to be built from Style.space alone: at a compact scale (0.3 here) Style.space
  // floors a 4 px mark at 1 px while the mark stayed 2 px, leaving the row's cell
  // half a pixel narrower than the mark it centres.
  const dense = space(0.3)
  assert.equal(G.dot(dense, 1, true), 2)
  assert.equal(G.barThickness(dense, 1), 2)
  assert.equal(G.cell(dense, 1, true), 2)      // 1 before the floor had one owner
  assert.equal(G.cell(dense, 1, false), 2)
  // At 2x the same compact theme the hairline is a whole pixel, so the floor no
  // longer binds.
  assert.equal(G.cell(dense, 2, true), 1)
  for (const scale of [0.2, 0.3, 0.375, 0.5, 1, 1.25, 1.5, 3]) {
    for (const dpr of [1, 1.25, 1.5, 2, 3]) {
      for (const dense of [false, true]) {
        assert.ok(G.cell(space(scale), dpr, dense) >= G.dot(space(scale), dpr, dense),
          `cell vs dot at scale ${scale}, dpr ${dpr}, dense ${dense}`)
        assert.ok(G.cell(space(scale), dpr, dense) >= G.barThickness(space(scale), dpr),
          `cell vs bar at scale ${scale}, dpr ${dpr}, dense ${dense}`)
      }
    }
  }
  // ...and the floor rule the cell derives from has one owner.
  assert.equal(G.hairline(1), 2)
  assert.equal(G.hairline(2), 1)
})
