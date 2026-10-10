// Pinned button slots: a command runs, no file listing is built, junk is dropped.
// Buttons.js is plain JS with no Qt globals, so it runs in the same vm context as
// DockModel.js and SettingsSearch.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = new URL("../../Buttons.js", import.meta.url)
const B = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), B)
// Values from the vm realm have foreign prototypes; compare plain copies.
const plain = (v) => JSON.parse(JSON.stringify(v))

test("a button keeps its command, name and icon", () => {
  const out = plain(B.boundPinnedButtons([{ command: "/usr/bin/foo --bar", name: "Foo", icon: "user-desktop" }]))
  assert.deepEqual(out, [{ command: "/usr/bin/foo --bar", name: "Foo", icon: "user-desktop" }])
})

test("name and icon fall back when missing", () => {
  const out = plain(B.boundPinnedButtons([{ command: "true" }]))
  assert.equal(out[0].name, "Button")
  assert.equal(out[0].icon, "application-x-executable")
})

test("a slot without a command is dropped", () => {
  assert.deepEqual(plain(B.boundPinnedButtons([{ name: "No command" }, { command: "" }, { command: "   " }])), [])
})

test("a slot with a non-string command is dropped", () => {
  assert.deepEqual(plain(B.boundPinnedButtons([{ command: 42 }, { command: { nested: true } }])), [])
})

test("the command is trimmed and length-capped", () => {
  const long = "x".repeat(4000)
  const out = plain(B.boundPinnedButtons([{ command: "  /usr/bin/foo  " }, { command: long }]))
  assert.equal(out[0].command, "/usr/bin/foo")
  assert.equal(out[1].command.length, B.MAX_BUTTON_COMMAND)
})

test("name and icon are length-capped too", () => {
  const out = plain(B.boundPinnedButtons([{ command: "true", name: "n".repeat(500), icon: "i".repeat(500) }]))
  assert.equal(out[0].name.length, B.MAX_BUTTON_NAME)
  assert.equal(out[0].icon.length, B.MAX_BUTTON_ICON)
})

test("at most MAX_PINNED_BUTTONS survive", () => {
  const many = []
  for (let i = 0; i < 50; i++) many.push({ command: "cmd" + i })
  const out = plain(B.boundPinnedButtons(many))
  assert.equal(out.length, B.MAX_PINNED_BUTTONS)
  assert.equal(out[0].command, "cmd0")
})

test("array-like objects and non-arrays are ignored", () => {
  assert.deepEqual(plain(B.boundPinnedButtons({ length: 1, 0: { command: "x" } })), [])
  assert.deepEqual(plain(B.boundPinnedButtons(null)), [])
  assert.deepEqual(plain(B.boundPinnedButtons("nope")), [])
})

test("nothing in the input object is carried through", () => {
  const out = plain(B.boundPinnedButtons([{ command: "true", extra: "x", path: "/tmp" }]))
  assert.deepEqual(Object.keys(out[0]).sort(), ["command", "icon", "name"])
})
