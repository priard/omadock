// Tests for DockOutput.js: whether the dock's output can take window captures.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKOUTPUT || new URL("../../DockOutput.js", import.meta.url)
const O = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), O)

test("a connected, enabled, powered output can capture", () => {
  assert.equal(O.outputAwake("DP-1", { name: "DP-1", lastIpcObject: { disabled: false, dpmsStatus: true } }), true)
  // Before the first IPC refresh the monitor carries no state: trust it.
  assert.equal(O.outputAwake("DP-1", { name: "DP-1", lastIpcObject: {} }), true)
  assert.equal(O.outputAwake("DP-1", { name: "DP-1" }), true)
})

test("no output, the fallback output, a disabled or powered-off one cannot", () => {
  assert.equal(O.outputAwake("", null), false)
  assert.equal(O.outputAwake("DP-1", null), false)
  assert.equal(O.outputAwake("FALLBACK", { name: "FALLBACK", lastIpcObject: {} }), false)
  assert.equal(O.outputAwake("DP-1", { name: "DP-1", lastIpcObject: { disabled: true, dpmsStatus: true } }), false)
  assert.equal(O.outputAwake("DP-1", { name: "DP-1", lastIpcObject: { disabled: false, dpmsStatus: false } }), false)
})

test("a monitor object for another output does not count", () => {
  assert.equal(O.outputAwake("DP-1", { name: "HDMI-A-1", lastIpcObject: { dpmsStatus: true } }), false)
})
