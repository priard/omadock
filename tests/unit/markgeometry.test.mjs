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
  assert.equal(G.cell(space(1), 1, false, false), 5)   // 5px dot
  assert.equal(G.cell(space(1), 1, true, false), 4)    // dense
  assert.equal(G.cell(space(1), 1, false, true), 4)    // side column uses the dense dot
  assert.equal(G.cell(space(1), 2, false, false), 5)
  assert.equal(G.cell(space(1.5), 1.5, false, false), 8)   // a denser theme, at 1.5x
})

test("dot: the mark itself, a hairline at the very least", () => {
  assert.equal(G.dot(space(1), 1, false, false), 5)
  assert.equal(G.dot(space(1), 1, true, false), 4)
  assert.equal(G.dot(space(1), 1, false, true), 4)
  assert.equal(G.dot(space(1), 4, false, false), 5)
  // A theme too dense to draw a whole pixel still gets 2/dpr.
  assert.equal(G.dot(() => 1, 1, false, false), 2)
  assert.equal(G.dot(() => 1, 1, true, true), 2)
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

test("a plate reserves exactly the cell the row draws the column in", () => {
  // The pair that used to disagree: the label sized the column from its own copy
  // of the number. A side column draws the dense dot, which is a bar's width, so
  // the reserved room is one cell at every scale and density.
  for (const scale of [1, 1.25, 1.5, 3]) {
    for (const dpr of [1, 1.25, 1.5, 2, 3]) {
      for (const dense of [false, true]) {
        const col = plain(G.column(space(scale), dpr))
        assert.equal(col.width, G.cell(space(scale), dpr, dense, true),
          `column width vs the row's cell at scale ${scale}, dpr ${dpr}, dense ${dense}`)
      }
    }
  }
  // ...and it is the room plus the plate's own padding that a label measures.
  assert.deepEqual(plain(G.column(space(1), 1)), { edge: 1, width: 4, gap: 5 })
})
