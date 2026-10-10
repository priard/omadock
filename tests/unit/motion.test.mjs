// Tests for DockMotion.js, the one source of the dock's animation timings.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMOTION || new URL("../../DockMotion.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
const plain = (v) => JSON.parse(JSON.stringify(v))

test("normalizeLevel keeps the three levels and defaults to full", () => {
  assert.equal(M.normalizeLevel("full"), "full")
  assert.equal(M.normalizeLevel("Reduced"), "reduced")
  assert.equal(M.normalizeLevel("off"), "off")
  for (const v of [undefined, null, "", "fast", 3, true]) assert.equal(M.normalizeLevel(v), "full")
})

test("full animates everything", () => {
  assert.deepEqual(plain(M.plan("full")), { level: "full", fast: 120, base: 180, slow: 300, hover: 110, press: 90,
    layout: true, scale: true, rise: true, oneShots: true, reveal: true, fade: true })
})

test("reduced keeps the fades and their timings, nothing that moves", () => {
  assert.deepEqual(plain(M.plan("reduced")), { level: "reduced", fast: 120, base: 180, slow: 300, hover: 110, press: 90,
    layout: false, scale: false, rise: false, oneShots: false, reveal: false, fade: true })
})

test("off is instant", () => {
  assert.deepEqual(plain(M.plan("off")), { level: "off", fast: 0, base: 0, slow: 0, hover: 0, press: 0,
    layout: false, scale: false, rise: false, oneShots: false, reveal: false, fade: false })
})

test("plan normalizes what it is given", () => {
  assert.equal(M.plan("bogus").level, "full")
})
