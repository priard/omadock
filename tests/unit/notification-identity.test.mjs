import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

// The notification path's answer for every id spelling that names a CLI or
// agent product.
//
// The ownership pass gave cliAppId ONE table, and the task HUD's stored-id
// contract needs that table to canonicalise all nine AI/agent spellings
// (`claude-code` -> `claude`). cliAppId also feeds the notification path's
// candidate sets, so the widening there had to be proved rather than assumed:
// a live notification from Claude Code, Windsurf or Cursor cannot be produced
// in CI, so the ANSWERS are captured from the tree before the pass (`409d6ab`)
// and pinned here, and the property that no candidate set shrank is asserted
// directly. Every route below is that tree's own
// `findNotificationTargets(entries, rows, {app: spelling, ...}).map(e => e.appId)`
// against the twelve-entry dock below, and every `cands` array is that tree's
// `getCandidates(spelling)`.
//
// HOW MUCH OF THAT TABLE IS ACTUALLY LOAD-BEARING was measured by killing its
// rules one at a time, not reasoned about. getCandidates() also splits an id on
// dots and dashes, so for 26 of the 28 spellings the canonical name is in the
// token set whatever cliAppId says: with the `claude-code -> claude` rule
// deleted, every route in CASES is unchanged and all four tests below stay
// green - which is the CORRECT outcome, since nothing observable moved. Only
// the agy family depends on the table (`agy` splits to itself, so `antigravity`
// can only arrive through cliAppId): with that one rule dead, route("agy") is
// "" and three of the four tests fail, naming `agy` and `org.omarchy.agy`.

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)

// The module runs in its own realm, so the arrays it returns have that realm's
// Array.prototype and deepStrictEqual rejects them against a literal. Every
// array this file asserts on is copied into this realm first.
const host = (list) => Array.from(list)
const route = (spelling) => host(M.findNotificationTargets(entries, rows,
  { app: spelling, appIcon: "", summary: "s", body: "" })).map((e) => e.appId)

// The dock the captured routes were taken against.
const DOCK = ["claude", "windsurf", "cursor", "ghostty", "foot", "footclient", "antigravity",
  "btop", "aider", "ollama", "copilot", "interpreter"]
const entries = DOCK.map((appId) => ({ appId }))
const rows = DOCK.map((id) => ({ id, appId: id, name: id, icon: id + ".svg" }))

// [spelling, the tile it resolved to before the pass, the candidate tokens that
// tree matched with]. "" means the notification resolved to no tile at all.
const CASES = [
  ["claude", "claude", ["claude"]],
  ["claude-code", "claude", ["claude-code", "claude", "code"]],
  ["com.anthropic.claude", "claude", ["com.anthropic.claude", "anthropic", "claude"]],
  ["aider", "aider", ["aider"]],
  ["aider-chat", "aider", ["aider-chat", "aider"]],
  ["cursor", "cursor", ["cursor"]],
  ["cursor-bin", "cursor", ["cursor-bin", "cursor"]],
  ["com.cursor.cursor", "cursor", ["com.cursor.cursor", "cursor"]],
  ["com.codeium.windsurf", "windsurf", ["com.codeium.windsurf", "codeium", "windsurf"]],
  ["windsurf", "windsurf", ["windsurf"]],
  ["ollama", "ollama", ["ollama"]],
  ["ollama-app", "ollama", ["ollama-app", "ollama"]],
  ["copilot", "copilot", ["copilot"]],
  ["github-copilot-cli", "copilot", ["github-copilot-cli", "copilot", "cli"]],
  ["interpreter", "interpreter", ["interpreter"]],
  ["open-interpreter", "interpreter", ["open-interpreter", "open", "interpreter"]],
  ["agy", "antigravity", ["antigravity"]],
  ["org.omarchy.agy", "antigravity", ["antigravity"]],
  ["antigravity", "antigravity", ["antigravity"]],
  ["btop", "btop", ["btop"]],
  ["org.omarchy.btop", "btop", ["btop"]],
  ["org.omarchy.btop-cpu", "btop", ["btop"]],
  ["foot", "foot", ["foot"]],
  ["footclient", "footclient", ["footclient"]],
  ["ghostty", "ghostty", ["ghostty"]],
  ["com.mitchellh.ghostty", "ghostty", ["com.mitchellh.ghostty", "mitchellh", "ghostty"]],
  ["ghostty-gui", "ghostty", ["ghostty-gui", "ghostty"]],
  ["codeium", "", ["codeium"]],
]

test("every CLI/agent spelling still routes its notification to the same tile", () => {
  const wrong = []
  for (const [spelling, want] of CASES) {
    const got = route(spelling).sort().join(",")
    if (got !== want) wrong.push(`${spelling}: ${JSON.stringify(got)} (before the pass: ${JSON.stringify(want)})`)
  }
  assert.deepEqual(wrong, [], wrong.join("; "))
})

test("canonicalising an id never makes its candidate set smaller", () => {
  // The widening is only safe as a superset: a candidate the old tree matched
  // with that the new one dropped is a notification that could stop arriving.
  const shrunk = []
  for (const [spelling, , before] of CASES) {
    const now = host(M.getCandidates(spelling))
    const lost = before.filter((c) => !now.includes(c))
    if (lost.length > 0) shrunk.push(`${spelling} lost ${JSON.stringify(lost)}`)
  }
  assert.deepEqual(shrunk, [], shrunk.join("; "))

  // ...and the extra tokens are the raw spelling plus its canonical name, which
  // is what makes the set a superset rather than a different set.
  assert.deepEqual(host(M.getCandidates("claude-code")), ["claude-code", "claude", "code"])
  assert.deepEqual(host(M.getCandidates("com.codeium.windsurf")), ["com.codeium.windsurf", "windsurf", "codeium"])
  assert.ok(host(M.getCandidates("org.omarchy.btop-cpu")).includes("btop"))
})

test("the badge count for an id spelling is unchanged", () => {
  // The other notification surface. notificationAliasIds extends the list only
  // for the two Omarchy TUI products, so every AI/agent spelling still answers
  // [raw] and those two answer what they answered before the pass (captured
  // from 409d6ab; all six were already multi-spelling, none changed).
  const TUI = {
    agy: ["agy", "antigravity", "agy", "org.omarchy.agy"],
    "org.omarchy.agy": ["org.omarchy.agy", "antigravity", "agy", "org.omarchy.agy"],
    antigravity: ["antigravity", "antigravity", "agy", "org.omarchy.agy"],
    btop: ["btop", "btop", "org.omarchy.btop"],
    "org.omarchy.btop": ["org.omarchy.btop", "btop", "org.omarchy.btop"],
    "org.omarchy.btop-cpu": ["org.omarchy.btop-cpu", "btop", "org.omarchy.btop"],
  }
  for (const [spelling] of CASES)
    assert.deepEqual(host(M.notificationAliasIds(spelling)), TUI[spelling] || [spelling], spelling)
})

test("the canonical name reaches the candidate set wherever the split does not", () => {
  // The table's only route into the notification path is the canonical name it
  // contributes to getCandidates(). Where the generic dot/dash split already
  // yields that name the table is redundant (measured above: killing those
  // rules changes no route and keeps this file green); where it does not, the
  // table is the only source - so these two spellings are pinned directly, and
  // they are the ones that go red when the rule is removed.
  for (const [spelling] of CASES) {
    const cands = host(M.getCandidates(spelling))
    const canon = M.cliAppId(spelling)
    assert.ok(cands.includes(canon),
      `${spelling}: candidates ${JSON.stringify(cands)} lost its canonical name ${canon}`)
  }
  assert.equal(M.cliAppId("agy"), "antigravity")
  assert.equal(M.cliAppId("org.omarchy.agy"), "antigravity")
})

test("the two named pairs behave the same way in the notification path", () => {
  // `foot` must never reach `footclient` - the same rule the task HUD keeps.
  assert.deepEqual(route("foot"), ["foot"])
  assert.deepEqual(route("footclient"), ["footclient"])
  // ...and a reverse-DNS id and its bare name are one app, in both directions.
  assert.deepEqual(route("com.mitchellh.ghostty"), ["ghostty"])
  assert.deepEqual(route("ghostty"), ["ghostty"])
})
