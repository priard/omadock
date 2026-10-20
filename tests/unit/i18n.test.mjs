// The translation catalogs (i18n/*.json, read by Omarchy 4.5's
// Commons.Translations through components/strings/Tr.qml): every explicit
// Tr.t / Tr.tn call has its English entry, and each translation matches the
// English one it replaces.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync, statSync } from "node:fs"
import { join } from "node:path"

const root = new URL("../../", import.meta.url).pathname
const en = JSON.parse(readFileSync(join(root, "i18n/en.json"), "utf8"))
const catalogs = readdirSync(join(root, "i18n")).filter((f) => f.endsWith(".json") && f !== "en.json")

function sources(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name.startsWith(".") || ["tests", "bench", "docs", "node_modules"].includes(name)) continue
    const path = join(dir, name)
    if (statSync(path).isDirectory()) sources(path, out)
    else if (/\.(qml|js)$/.test(name)) out.push(path)
  }
  return out
}

const holes = (text) => [...String(text).matchAll(/%\d/g)].map((m) => m[0]).sort().join(",")
const forms = (value) => (typeof value === "object" ? Object.values(value) : [value])

test("every Tr.t call has its English text in en.json", () => {
  const call = /\b(?:Tr\.t|tr)\(\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"/g
  for (const file of sources(root)) {
    for (const m of readFileSync(file, "utf8").matchAll(call)) {
      assert.ok(m[1] in en, `${m[1]} (${file.slice(root.length)}) is missing from en.json`)
      assert.equal(en[m[1]], JSON.parse(`"${m[2]}"`), `${m[1]}: en.json and the code disagree`)
    }
  }
})

for (const name of catalogs) {
  const catalog = JSON.parse(readFileSync(join(root, "i18n", name), "utf8"))

  test(`${name}: only keys en.json has, with the same placeholders`, () => {
    for (const [key, value] of Object.entries(catalog)) {
      assert.ok(key in en, `${name}: ${key} is not in en.json`)
      assert.equal(typeof value === "object", typeof en[key] === "object", `${name}: ${key} plural shape differs`)
      const want = holes(forms(en[key])[forms(en[key]).length - 1])
      for (const form of forms(value)) assert.equal(holes(form), want, `${name}: ${key} placeholders differ`)
    }
  })

  test(`${name}: plural entries carry an "other" form`, () => {
    for (const [key, value] of Object.entries(catalog))
      if (typeof value === "object") assert.ok("other" in value, `${name}: ${key} has no "other"`)
  })
}
