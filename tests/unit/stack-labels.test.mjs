// Folder stack header count and footer for folders the scan could not
// list in full (more than list-folder.py's MAX_SCAN entries).
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
// The two stack labels live in DockLabels.js now; the assertions are unchanged.
vm.runInContext(readFileSync(new URL("../../DockLabels.js", import.meta.url), "utf8"), M)

test("stackCountLabel: plain count, capped count, nothing for empty", () => {
  assert.equal(M.stackCountLabel(31, false), "31")
  assert.equal(M.stackCountLabel(20000, true), "20000+")
  assert.equal(M.stackCountLabel(0, false), "")
})

test("stackMoreLabel: entries left over", () => {
  assert.equal(M.stackMoreLabel(310, 300, false), "+ 10 more")
  assert.equal(M.stackMoreLabel(300, 300, false), "")
})

test("stackMoreLabel: a capped scan says there are at least that many", () => {
  assert.equal(M.stackMoreLabel(20000, 300, true), "+ 19700+ more")
})

// The boundaries, captured from DockModel.js before the move: nothing counts
// a missing, negative or unusable number, and a partial difference floors to
// whole entries.
test("both labels: what a missing or fractional count prints", () => {
  assert.equal(M.stackCountLabel(NaN, false), "")
  assert.equal(M.stackCountLabel(-3, false), "")
  assert.equal(M.stackCountLabel(null, true), "")
  assert.equal(M.stackCountLabel(3.7, false), "3")
  assert.equal(M.stackCountLabel(99, true), "99+")
  assert.equal(M.stackMoreLabel(0, 0, false), "")
  assert.equal(M.stackMoreLabel(2, 5, false), "")
  assert.equal(M.stackMoreLabel(NaN, NaN, false), "")
  assert.equal(M.stackMoreLabel(7.9, 2.9, false), "+ 5 more")
})
