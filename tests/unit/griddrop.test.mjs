// Tests for DockGridDrop.js: where an app from Omarchy's app grid lands.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKGRIDDROP || new URL("../../DockGridDrop.js", import.meta.url)
const G = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), G)

const strip = (id) => String(id || "").replace(/\.desktop$/, "")
const app = (appId) => ({ kind: "app", appId })
const ids = (res) => JSON.parse(JSON.stringify(res.row)).map((r) => r.appId || "group:" + r.groupId)
const row = [app("zen"), { kind: "group", groupId: "g1" }, app("chromium")]

test("an unpinned app is inserted where its gap stood", () => {
  assert.deepEqual(ids(G.gridDrop(row, "foot", false, 1, strip)), ["zen", "foot", "group:g1", "chromium"])
  assert.deepEqual(ids(G.gridDrop(row, "foot", false, 3, strip)), ["zen", "group:g1", "chromium", "foot"])
})

test("a pinned app moves to the gap, and staying put changes nothing", () => {
  assert.deepEqual(ids(G.gridDrop(row, "chromium", true, 0, strip)), ["chromium", "zen", "group:g1"])
  assert.deepEqual(ids(G.gridDrop(row, "zen", true, 3, strip)), ["group:g1", "chromium", "zen"])
  assert.deepEqual(JSON.parse(JSON.stringify(G.gridDrop(row, "zen", true, 0, strip))), {})
  assert.deepEqual(JSON.parse(JSON.stringify(G.gridDrop(row, "zen", true, 1, strip))), {})
})

test("a desktop-file suffix in the run still matches", () => {
  assert.deepEqual(ids(G.gridDrop([app("foot.desktop"), app("zen")], "foot", true, 2, strip)), ["zen", "foot.desktop"])
})

test("an app pinned inside a group stays there", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(G.gridDrop(row, "discord", true, 0, strip))), {})
})

test("an empty run pins through togglePin unless already pinned", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(G.gridDrop([], "foot", false, -1, strip))), { pin: true })
  assert.deepEqual(JSON.parse(JSON.stringify(G.gridDrop([], "foot", true, -1, strip))), {})
})
