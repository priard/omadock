// Tests for DockPresets.js, the looks a fresh install offers: the shape a
// shipped preset must hold, and the merge that puts them in front of the
// presets a user saved. Plain JS, run in a vm context like DockModel.js (the
// merge fills each shipped look through pickLook, so both modules load).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const root = new URL("../../", import.meta.url)
const ctx = vm.createContext({ console, Quickshell: { iconPath: () => "" } })
for (const file of ["DockModel.js", "DockPresets.js"])
  vm.runInContext(readFileSync(new URL(file, root), "utf8"), ctx)
const plain = (v) => JSON.parse(JSON.stringify(v))

const SHIPPED = plain(ctx.SHIPPED)
const merged = (user) => plain(ctx.merge(user, ctx.pickLook))

test("shipped presets are well formed and distinct", () => {
  assert.ok(SHIPPED.length >= 1, "at least one look ships")
  const ids = new Set()
  const names = new Set()
  for (const p of SHIPPED) {
    assert.match(p.id, /^[A-Za-z0-9_]{1,64}$/, `${p.name} has a storable id`)
    assert.doesNotMatch(p.id, /^preset_\d+$/, `${p.name} cannot take a saved preset's id`)
    assert.equal(p.name, ctx.cleanPresetName(p.name), `${p.name} is a clean, trimmed name`)
    assert.ok(p.name.length > 0 && p.name.length <= ctx.MAX_PRESET_NAME)
    assert.ok(!ids.has(p.id) && !names.has(p.name), `${p.name} is unique`)
    ids.add(p.id)
    names.add(p.name)
  }
})

test("every shipped look fills out to the whole look model", () => {
  for (const p of SHIPPED) {
    const look = plain(ctx.pickLook(p.look))
    assert.deepEqual(Object.keys(look).sort(), plain(ctx.LOOK_KEYS).sort(),
      `${p.name} holds every look key`)
    for (const [k, v] of Object.entries(look)) {
      const scalar = typeof v === "string" || typeof v === "boolean"
        || (typeof v === "number" && isFinite(v))
      assert.ok(scalar, `${p.name}.${k} is a scalar a preset can hold`)
    }
  }
})

test("shipped looks differ from each other", () => {
  const seen = new Map()
  for (const p of SHIPPED) {
    const key = JSON.stringify(plain(ctx.pickLook(p.look)))
    assert.ok(!seen.has(key), `${p.name} differs from ${seen.get(key)}`)
    seen.set(key, p.name)
  }
})

test("a dock with no saved presets still offers every shipped look", () => {
  const list = merged([])
  assert.equal(list.length, SHIPPED.length)
  assert.deepEqual(list.map((p) => p.name), SHIPPED.map((p) => p.name))
  assert.ok(list.every((p) => p.builtin === true), "each entry is marked as shipped")
  assert.equal(plain(ctx.userCount(list)), 0)
  assert.deepEqual(plain(ctx.userOnly(list)), [])
})

test("saved presets follow the shipped ones and stay untouched", () => {
  const saved = [
    { id: "preset_1", name: "Mine", look: plain(ctx.pickLook({ grain: 0.5, iconStyle: "mono" })) },
    { id: "preset_2", name: "Other", look: plain(ctx.pickLook({})) }
  ]
  const list = merged(saved)
  assert.equal(list.length, SHIPPED.length + saved.length)
  assert.deepEqual(list.slice(-saved.length), saved, "the user's own entries are kept verbatim")
  assert.deepEqual(plain(ctx.userOnly(list)), saved)
  assert.equal(plain(ctx.userCount(list)), saved.length)
  // What the dock writes back is exactly what the user had.
  assert.deepEqual(plain(ctx.boundPresets(ctx.userOnly(list))), saved)
})

test("thepathless:ristretto pins the look the maintainer's dock runs", () => {
  const r = merged([]).find((p) => p.name === "thepathless:ristretto")
  assert.ok(r, "the owner's look ships")
  // Its stated keys, then the defaults for every key it leaves out.
  assert.deepEqual(plain(ctx.pickLook(r.look)), plain(ctx.pickLook({
    bgFill: "gradient", gradientPreset: "forest", gradientStrength: 0.25, grain: 0.2,
    dividerGeometry: "long", dividerStyle: "custom",
    iconStyle: "dots", iconGrid: 8, iconContrast: 0.4, iconStrength: 0.45, iconSize: 34,
    hoverEffect: "glitch", opacity: "theme", shape: "theme",
    showBorder: false, showShadow: false
  })))
  assert.equal(r.look.iconStyle, "dots")
  assert.equal(r.look.gradientPreset, "forest")
  assert.equal(r.look.showShadow, false)
  assert.equal(r.look.hoverEffect, "glitch")
  assert.equal(r.look.opacity, "theme")
})
