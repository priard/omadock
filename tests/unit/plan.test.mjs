// The tiling-place arithmetic, checked against layouts captured from a live Hyprland
// 0.56.2 session (Omarchy, 1920x1200 at scale 1.5): three and four windows on one
// workspace, before parking the master and after restoring it.
//
// Plan.js is plain JS with no Qt globals, so it runs in the same vm context as
// DockModel.js, SettingsSearch.js and Buttons.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = new URL("../../Plan.js", import.meta.url)
const P = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), P)
// Values from the vm realm have foreign prototypes; compare plain copies.
const plain = (v) => JSON.parse(JSON.stringify(v))

// ---------------------------------------------------------------- fixtures
// One window as hyprctl -j clients sends it, with all of its fields.
const REAL_WINDOW = {
"address": "0x617b9ce838c0",
"mapped": true,
"hidden": false,
"visible": true,
"acceptsInput": true,
"at": [
12,
38
],
"size": [
1256,
750
],
"workspace": {
"id": 1,
"name": "1"
},
"floating": false,
"monitor": 0,
"class": "com.nousresearch.hermes",
"title": "Hermes",
"initialClass": "com.nousresearch.hermes",
"initialTitle": "Hermes",
"pid": 41166,
"xwayland": false,
"pinned": false,
"pinFullscreened": false,
"fullscreen": 0,
"fullscreenClient": 0,
"fullscreenHandler": "default",
"allowedOverFullscreen": true,
"grouped": [],
"tags": [
"default-opacity*"
],
"swallowing": "0x0",
"focusHistoryID": 1,
"inhibitingIdle": false,
"xdgTag": "",
"xdgDescription": "",
"contentType": "none",
"tearingHint": false,
"stableId": "18000041"
}

// Three windows: the rectangles come back *different* - the tree changed shape, so no
// exchange can rebuild the original layout.
const THREE_RECORDED = [
{
"address": "0x617b9e9c9920",
"at": [
12,
38
],
"size": [
621,
750
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e9c8100",
"at": [
647,
38
],
"size": [
621,
368
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9dae81c0",
"at": [
647,
420
],
"size": [
621,
368
],
"workspace": {
"name": "9"
}
}
]
const THREE_AFTER = [
{
"address": "0x617b9e9c8100",
"at": [
12,
38
],
"size": [
621,
750
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9dae81c0",
"at": [
647,
38
],
"size": [
301,
750
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e9c9920",
"at": [
962,
38
],
"size": [
306,
750
],
"workspace": {
"name": "9"
}
}
]

// Four windows: the same four rectangles come back, each with the wrong window in it.
const FOUR_RECORDED = [
{
"address": "0x617b9e9c9920",
"at": [
12,
38
],
"size": [
621,
750
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e911640",
"at": [
647,
38
],
"size": [
621,
368
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e89ea60",
"at": [
647,
420
],
"size": [
301,
368
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e8922d0",
"at": [
962,
420
],
"size": [
306,
368
],
"workspace": {
"name": "9"
}
}
]
const FOUR_AFTER = [
{
"address": "0x617b9e911640",
"at": [
12,
38
],
"size": [
621,
750
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e89ea60",
"at": [
647,
38
],
"size": [
621,
368
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e8922d0",
"at": [
647,
420
],
"size": [
301,
368
],
"workspace": {
"name": "9"
}
},
{
"address": "0x617b9e9c9920",
"at": [
962,
420
],
"size": [
306,
368
],
"workspace": {
"name": "9"
}
}
]

const rows = (windows) => windows.map((w) => ({
  address: P.normalizeAddress(w.address),
  rect: { x: w.at[0], y: w.at[1], w: w.size[0], h: w.size[1] }
}))
const layoutOf = (windows) => {
  const map = {}
  for (const w of windows) map[P.normalizeAddress(w.address)] = { x: w.at[0], y: w.at[1], w: w.size[0], h: w.size[1] }
  return map
}
const assignment = (list) => {
  const out = {}
  for (const r of list) out[r.address] = [r.rect.x, r.rect.y, r.rect.w, r.rect.h]
  return out
}

test("normalizeAddress accepts both spellings and nothing else", () => {
  assert.equal(P.normalizeAddress("0xAbC123"), "0xabc123")
  assert.equal(P.normalizeAddress("AbC123"), "0xabc123")
  assert.equal(P.normalizeAddress("  0x1  "), "0x1")
  assert.equal(P.normalizeAddress(""), "")
  assert.equal(P.normalizeAddress(null), "")
  assert.equal(P.normalizeAddress(undefined), "")
})

test("parseClientRects reads hyprctl's list, extra fields and all", () => {
  const map = plain(P.parseClientRects(JSON.stringify([REAL_WINDOW, THREE_RECORDED[1]])))
  const first = map[P.normalizeAddress(REAL_WINDOW.address)]
  assert.deepEqual(first, {
    x: REAL_WINDOW.at[0], y: REAL_WINDOW.at[1],
    w: REAL_WINDOW.size[0], h: REAL_WINDOW.size[1],
    workspace: REAL_WINDOW.workspace.name
  })
  assert.equal(Object.keys(map).length, 2)
})

test("parseClientRects keeps junk and malformed input out", () => {
  assert.deepEqual(plain(P.parseClientRects("not json")), {})
  assert.deepEqual(plain(P.parseClientRects('{"length": 3}')), {})
  assert.deepEqual(plain(P.parseClientRects("")), {})
  assert.deepEqual(plain(P.parseClientRects(null)), {})
  const map = plain(P.parseClientRects(JSON.stringify([{ address: "0x1" }, { at: [0, 0] }])))
  assert.deepEqual(map, {})
})

test("windowsOnWorkspace orders the windows the way dwindle tiles them", () => {
  const rects = P.parseClientRects(JSON.stringify(FOUR_RECORDED))
  const ws = FOUR_RECORDED[0].workspace.name
  const ordered = plain(P.windowsOnWorkspace(rects, ws)).map((r) => r.address)
  assert.deepEqual(ordered, FOUR_RECORDED.map((w) => P.normalizeAddress(w.address)))
  assert.equal(P.windowCountOnWorkspace(rects, ws), 4)
  assert.deepEqual(plain(P.windowsOnWorkspace(rects, "99")), [])
})

test("rectsClose tolerates a few pixels and no more", () => {
  const a = { x: 12, y: 38, w: 621, h: 750 }
  assert.ok(P.rectsClose(a, { x: 14, y: 40, w: 619, h: 748 }))
  assert.ok(!P.rectsClose(a, { x: 20, y: 38, w: 621, h: 750 }))
  assert.ok(!P.rectsClose(a, null))
})

test("overlapArea measures the shared rectangle, not the distance", () => {
  assert.equal(P.overlapArea({ x: 0, y: 0, w: 10, h: 10 }, { x: 0, y: 0, w: 10, h: 10 }), 100)
  assert.equal(P.overlapArea({ x: 0, y: 0, w: 10, h: 10 }, { x: 5, y: 0, w: 10, h: 10 }), 50)
  assert.equal(P.overlapArea({ x: 0, y: 0, w: 10, h: 10 }, { x: 20, y: 0, w: 10, h: 10 }), 0)
})

test("ownerOfRect finds the recorded window for a rectangle, and only for one", () => {
  const layout = layoutOf(FOUR_RECORDED)
  assert.equal(P.ownerOfRect(layout, { x: 647, y: 420, w: 301, h: 368 }),
    P.normalizeAddress(FOUR_RECORDED[2].address))
  // one of the column rectangles from the three-window case belongs to nobody
  assert.equal(P.ownerOfRect(layout, { x: 647, y: 38, w: 301, h: 750 }), "")
})

test("occupantOfRect wants a window that really stands in the rectangle", () => {
  const rowsAfter3 = rows(THREE_AFTER)
  // the wide left column is the recorded master rectangle for the three-window case
  const master = { x: 12, y: 38, w: 621, h: 750 }
  assert.equal(P.occupantOfRect(rowsAfter3, master, ""), P.normalizeAddress(THREE_AFTER[0].address))
  // a window that only grazes it (less than OCCUPY_SHARE) is not an occupant
  assert.equal(P.occupantOfRect([{ address: "0xdead", rect: { x: 12, y: 300, w: 621, h: 368 } }], master, ""), "")
  assert.equal(P.occupantOfRect([], master, ""), "")
  assert.equal(P.occupantOfRect(rowsAfter3, null, ""), "")
})

test("firstWrongRect names a window that is not where it was", () => {
  const layout = layoutOf(FOUR_RECORDED)
  const wrong = P.firstWrongRect(rows(FOUR_AFTER), layout)
  assert.notEqual(wrong, "")
  assert.ok(Object.keys(layout).includes(wrong))
  // a state that matches the recording has nothing wrong in it
  assert.equal(P.firstWrongRect(rows(FOUR_RECORDED), layout), "")
})

test("the plan sorts the permutation Hyprland leaves behind (four windows, measured)", () => {
  const layout = layoutOf(FOUR_RECORDED)
  const before = rows(FOUR_AFTER)
  const plan = plain(P.slotSwapPlan(before, layout))
  assert.ok(plan.length > 0, "a permuted assignment needs exchanges")
  assert.ok(plan.length <= before.length - 1, "n-1 exchanges sort a permutation")
  // applying the plan must reproduce the recorded assignment exactly
  assert.deepEqual(assignment(plain(P.applyPlan(before, plan))), assignment(rows(FOUR_RECORDED)))
})

test("the plan is empty when the tree changed shape (three windows, measured)", () => {
  const layout = layoutOf(THREE_RECORDED)
  assert.deepEqual(plain(P.slotSwapPlan(rows(THREE_AFTER), layout)), [])
})

test("the plan is empty when everything is already home", () => {
  const layout = layoutOf(FOUR_RECORDED)
  assert.deepEqual(plain(P.slotSwapPlan(rows(FOUR_RECORDED), layout)), [])
})

test("a plan that cannot be applied leaves the rows alone", () => {
  const before = rows(FOUR_AFTER)
  assert.deepEqual(assignment(plain(P.applyPlan(before, [["0xnope", before[0].address]]))), assignment(before))
})

test("rectSignature tells two states apart and is stable for one", () => {
  const a = rows(FOUR_AFTER)
  assert.equal(P.rectSignature(a), P.rectSignature(rows(FOUR_AFTER)))
  assert.notEqual(P.rectSignature(a), P.rectSignature(rows(FOUR_RECORDED)))
  assert.equal(P.rectSignature([]), "")
})
