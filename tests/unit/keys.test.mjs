// Tests for DockKeys.js: keyed rows with a leaving state (KeyedListModel).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKKEYS || new URL("../../DockKeys.js", import.meta.url)
const K = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), K)
const plain = (v) => JSON.parse(JSON.stringify(v))
const keys = (rows) => rows.map((r) => r.key + (r.leaving ? "-" : ""))

test("first sync: rows in order, nothing fresh", () => {
  const t = plain(K.target([], ["a", "b"], true, 0, 180))
  assert.deepEqual(t.map((r) => [r.key, r.leaving, r.fresh, r.slot]), [["a", false, false, 0], ["b", false, false, 1]])
})

test("an added key is fresh after the first sync", () => {
  const r0 = K.target([], ["a", "b"], true, 0, 180)
  const t = plain(K.target(r0, ["a", "x", "b"], false, 10, 180))
  assert.deepEqual(t.map((r) => [r.key, r.fresh, r.slot]), [["a", false, 0], ["x", true, 1], ["b", false, 2]])
})

test("a removed key stays, leaving, where it was", () => {
  const r0 = K.target([], ["a", "b", "c"], true, 0, 180)
  const t = plain(K.target(r0, ["a", "c"], false, 100, 180))
  assert.deepEqual(keys(t), ["a", "b-", "c"])
  assert.equal(t[1].leaveAt, 280)
  assert.deepEqual(t.filter((r) => !r.leaving).map((r) => r.slot), [0, 1])
})

test("a leaving key that is wanted again revives in place", () => {
  const r0 = K.target([], ["a", "b", "c"], true, 0, 180)
  const r1 = K.target(r0, ["a", "c"], false, 100, 180)
  const t = plain(K.target(r1, ["a", "b", "c"], false, 150, 180))
  assert.deepEqual(keys(t), ["a", "b", "c"])
  assert.equal(t[1].fresh, false)
})

test("a second change keeps an earlier leaving row and its deadline", () => {
  const r0 = K.target([], ["a", "b", "c"], true, 0, 180)
  const r1 = K.target(r0, ["a", "c"], false, 100, 180)
  const t = plain(K.target(r1, ["c", "a"], false, 150, 180))
  assert.deepEqual(keys(t).filter((k) => !k.endsWith("-")), ["c", "a"])
  assert.equal(t.find((r) => r.key === "b").leaveAt, 280)
})

test("exitMs 0 drops removed keys at once", () => {
  const r0 = K.target([], ["a", "b"], true, 0, 0)
  assert.deepEqual(keys(plain(K.target(r0, ["b"], false, 5, 0))), ["b"])
})

test("expire drops rows past their deadline and recomputes slots", () => {
  const r0 = K.target([], ["a", "b", "c"], true, 0, 180)
  const r1 = K.target(r0, ["a", "c"], false, 100, 180)
  assert.equal(K.nextExpiry(r1), 280)
  assert.deepEqual(keys(plain(K.expire(r1, 279))), ["a", "b-", "c"])
  const e = plain(K.expire(r1, 280))
  assert.deepEqual(keys(e), ["a", "c"])
  assert.deepEqual(e.map((r) => r.slot), [0, 1])
  assert.equal(K.nextExpiry(e), -1)
})

test("row keys for tiles, folders, buttons and drives", () => {
  assert.equal(K.tileKey({ type: "single", win: { address: "0x1" } }), "win:0x1")
  assert.equal(K.tileKey({ type: "group", appId: "foot" }), "app:foot")
  assert.equal(K.folderKey({ path: "~/Downloads" }), "path:~/Downloads")
  assert.equal(K.folderKey({ command: "btop", name: "Top" }), "cmd:Top:btop")
  assert.equal(K.driveKey({ dev: "/dev/sdb1" }), "dev:/dev/sdb1")
})

test("a repeated key is one row (identical buttons are one button)", () => {
  const t = plain(K.target([], ["a", "b", "a"], true, 0, 180))
  assert.deepEqual(keys(t), ["a", "b"])
  const r1 = K.target(K.target([], ["a", "a"], true, 0, 180), ["a"], false, 10, 180)
  assert.deepEqual(keys(plain(r1)), ["a"])
})
