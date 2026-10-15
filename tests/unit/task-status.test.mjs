import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import vm from "node:vm"

// The two modules are loaded into separate contexts, the way QML loads them:
// DockTasks.js never imports DockModel.js, so app identity arrives as the `ids`
// argument at every call. DOCKTASKS / DOCKMODEL point either at another working
// tree, for a differential run against the tree before the ownership pass.
const tasksFile = process.env.DOCKTASKS || new URL("../../DockTasks.js", import.meta.url)
const modelFile = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(tasksFile, "utf8"), M)
const ID = vm.createContext({})
vm.runInContext(readFileSync(modelFile, "utf8"), ID)

test("normalizeTaskStatus: valid inputs and exit codes", () => {
  const successTask = M.normalizeTaskStatus(ID, "ghostty.desktop", "done", 0, "cargo build --release", 14)
  assert.equal(successTask.appId, "ghostty")
  assert.equal(successTask.status, "success")
  assert.equal(successTask.exitCode, 0)
  assert.equal(successTask.title, "cargo build --release")
  assert.equal(successTask.duration, 14)

  const failTask = M.normalizeTaskStatus(ID, "com.mitchellh.ghostty", "done", 101, "cargo test", 5)
  assert.equal(failTask.appId, "com.mitchellh.ghostty")
  assert.equal(failTask.status, "error")
  assert.equal(failTask.exitCode, 101)

  const runningTask = M.normalizeTaskStatus(ID, "Alacritty", "running", 0, "npm install", 0)
  assert.equal(runningTask.appId, "Alacritty")
  assert.equal(runningTask.status, "running")
})

test("normalizeTaskStatus: status keyword overrides and bounds", () => {
  const explicitErr = M.normalizeTaskStatus(ID, "foot", "error", 0, "make", 2)
  assert.equal(explicitErr.status, "error")

  const explicitRun = M.normalizeTaskStatus(ID, "kitty", "busy", 0, "sleep 10", 0)
  assert.equal(explicitRun.status, "running")

  const negativeDur = M.normalizeTaskStatus(ID, "xterm", "done", 0, "true", -10)
  assert.equal(negativeDur.duration, 0)

  const longTitle = "a".repeat(200)
  const clamped = M.normalizeTaskStatus(ID, "xterm", "done", 0, longTitle, 1)
  assert.equal(clamped.title.length, M.MAX_TASK_TITLE)

  assert.equal(M.normalizeTaskStatus(ID, "", "done", 0, "cmd", 0), null)
  assert.equal(M.normalizeTaskStatus(ID, null, "done", 0, "cmd", 0), null)
})

test("withTaskStatus and clearTaskStatusFor", () => {
  let map = {}
  const t1 = M.normalizeTaskStatus(ID, "alacritty", "done", 0, "gcc -O3", 4)
  map = M.withTaskStatus(ID, map, "alacritty", t1)
  assert.equal(map["alacritty"].title, "gcc -O3")

  // Clearing by exact ID
  map = M.clearTaskStatusFor(ID, map, "alacritty")
  assert.equal(map["alacritty"], undefined)

  // Matching through aliases/prefixes (e.g. Alacritty vs alacritty)
  map = M.withTaskStatus(ID, map, "Alacritty", t1)
  assert.ok(M.taskStatusFor(ID, map, "alacritty"))
  map = M.clearTaskStatusFor(ID, map, "alacritty")
  assert.equal(M.taskStatusFor(ID, map, "Alacritty"), null)

  // AI assistant aliases: agy and org.omarchy.agy normalize to antigravity
  const tAgy = M.normalizeTaskStatus(ID, "agy", "done", 0, "agent test", 3)
  assert.equal(tAgy.appId, "antigravity")
  map = M.withTaskStatus(ID, map, "agy", tAgy)
  assert.ok(M.taskStatusFor(ID, map, "antigravity"))
  assert.ok(M.taskStatusFor(ID, map, "org.omarchy.agy"))
  map = M.clearTaskStatusFor(ID, map, "antigravity")
  assert.equal(M.taskStatusFor(ID, map, "antigravity"), null)

  // Universal AI tools normalization
  assert.equal(M.normalizeTaskStatus(ID, "claude-code", "done", 0, "c", 1).appId, "claude")
  assert.equal(M.normalizeTaskStatus(ID, "com.anthropic.claude", "done", 0, "c", 1).appId, "claude")
  assert.equal(M.normalizeTaskStatus(ID, "aider-chat", "done", 0, "a", 1).appId, "aider")
  assert.equal(M.normalizeTaskStatus(ID, "cursor-bin", "done", 0, "c", 1).appId, "cursor")
  assert.equal(M.normalizeTaskStatus(ID, "com.codeium.windsurf", "done", 0, "w", 1).appId, "windsurf")
  assert.equal(M.normalizeTaskStatus(ID, "ollama-app", "done", 0, "o", 1).appId, "ollama")
  assert.equal(M.normalizeTaskStatus(ID, "github-copilot-cli", "done", 0, "g", 1).appId, "copilot")
  assert.equal(M.normalizeTaskStatus(ID, "open-interpreter", "done", 0, "i", 1).appId, "interpreter")

  // Primary + Fallback routing
  const tClaude = M.normalizeTaskStatus(ID, "claude|foot", "running", 0, "refactor", 0)
  assert.equal(tClaude.appId, "claude")
  assert.equal(tClaude.fallbackId, "foot")
  map = M.withTaskStatus(ID, map, "claude", tClaude)

  // Case A: Claude IS present on dock -> Claude gets badge, Foot does NOT
  const dockWithClaude = { pinned: [{ appId: "claude" }], running: [{ appId: "foot" }] }
  assert.equal(M.taskStatusFor(ID, map, "claude", dockWithClaude).appId, "claude")
  assert.equal(M.taskStatusFor(ID, map, "foot", dockWithClaude), null)

  // Case B: Claude is NOT present on dock -> Foot (host terminal) gets badge
  const dockWithoutClaude = { pinned: [{ appId: "foot" }], running: [] }
  assert.equal(M.taskStatusFor(ID, map, "claude", dockWithoutClaude).appId, "claude")
  assert.equal(M.taskStatusFor(ID, map, "foot", dockWithoutClaude).appId, "claude")

  // Clearing by terminal clears the fallback task too
  map = M.clearTaskStatusFor(ID, map, "foot")
  assert.equal(M.taskStatusFor(ID, map, "foot", dockWithoutClaude), null)
})

test("a task never bleeds onto an app whose id merely contains its own", () => {
  // foot and footclient are two separate terminal apps on the same desktop;
  // a task filed under one must not badge the other. The alias bridge is the
  // dot boundary only, which is what a reverse-DNS desktop id looks like.
  const map = M.withTaskStatus(ID, {}, "foot", M.normalizeTaskStatus(ID, "foot", "done", 0, "cargo build", 3))
  assert.ok(M.taskStatusFor(ID, map, "foot"))
  assert.equal(M.taskStatusFor(ID, map, "footclient"), null)
  assert.equal(M.taskStatusFor(ID, map, "kitty"), null)

  // The reverse-DNS form still reaches its bare name (both directions).
  const rdn = M.withTaskStatus(ID, {}, "com.mitchellh.ghostty", M.normalizeTaskStatus(ID, "com.mitchellh.ghostty", "done", 0, "test", 1))
  assert.ok(M.taskStatusFor(ID, rdn, "ghostty"))
  const bare = M.withTaskStatus(ID, {}, "ghostty", M.normalizeTaskStatus(ID, "ghostty", "done", 0, "test", 1))
  assert.ok(M.taskStatusFor(ID, bare, "com.mitchellh.ghostty"))
  // ...and a separate id that only shares a prefix stays untouched.
  assert.equal(M.taskStatusFor(ID, bare, "ghostty-gui"), null)
})

test("one owner of app identity, and the two pairs behave the same everywhere", () => {
  // Before the ownership pass the task path carried its own id table AND its
  // own strip (`stripDesktopId`, `isAppMatchSimple`), so the id spellings of one
  // app had two answers. They now come from DockModel, the only owner.
  assert.equal(M.isAppMatchSimple, undefined, "the task path must not carry a second matcher")
  assert.equal(M.stripDesktopId, undefined, "the task path must not carry a second id table")
  assert.equal(typeof ID.cliAppId, "function")
  assert.equal(typeof ID.isAppMatch, "function")

  // The two pairs the contract names: every spelling of them is answered the
  // same way by the task lookup, by the model's matcher and by the model's
  // entry lookup. `foot` must never reach `footclient`; a reverse-DNS id and
  // its bare name are one app in both directions.
  for (const [a, b, same] of [["foot", "footclient", false],
    ["com.mitchellh.ghostty", "ghostty", true], ["ghostty", "com.mitchellh.ghostty", true]]) {
    const task = M.normalizeTaskStatus(ID, a, "done", 0, "cargo build", 3)
    const map = M.withTaskStatus(ID, {}, task.appId, task)
    assert.equal(!!M.taskStatusFor(ID, map, b), same, `${a} vs ${b}: the task path disagrees`)
    assert.equal(ID.isAppMatch(a, b), same, `${a} vs ${b}: the model matcher disagrees`)
    assert.equal(ID.isAppMatch(b, a), same, `${b} vs ${a}: the model matcher is not symmetric`)
    assert.ok(M.taskStatusFor(ID, map, a), `${a}: the task cannot find its own tile`)
    const viaTask = !!M.taskStatusFor(ID, map, b)
    assert.equal(viaTask, ID.isAppMatch(a, b), `${a} vs ${b}: the two paths disagree`)
  }

  // Where the two rules deliberately differ. The model's matcher widens with
  // candidate tokens for notifications; the task path cannot, because a task
  // must attach to exactly one tile - this is the bleed v4.6.0 shipped a fix
  // for, and chaining the task path to isAppMatch re-introduced it here (the
  // earlier run of this file failed on exactly this line).
  assert.equal(ID.isAppMatch("ghostty", "ghostty-gui"), true)
  const gt = M.normalizeTaskStatus(ID, "ghostty", "done", 0, "test", 1)
  const gtMap = M.withTaskStatus(ID, {}, gt.appId, gt)
  assert.equal(M.taskStatusFor(ID, gtMap, "ghostty-gui"), null,
    "a task must not bleed onto an app that merely shares its prefix")

  // The canonicaliser is one function, so the stored id and every compared id
  // are spelled by the same owner.
  assert.equal(M.normalizeTaskStatus(ID, "claude-code", "done", 0, "c", 1).appId, ID.cliAppId("claude-code"))
  assert.equal(M.normalizeTaskStatus(ID, "agy", "done", 0, "c", 1).appId, ID.cliAppId("agy"))
  assert.equal(M.normalizeTaskStatus(ID, "ghostty.desktop", "done", 0, "c", 1).appId, ID.cliAppId("ghostty.desktop"))
})

test("task status has one owner, and every reader goes through it", () => {
  // The host's shared store is the only writable task map; Dock.qml exposes a
  // read-only view of it. Two maps meant no reader could tell which was
  // authoritative (components/DockItem.qml read whichever was non-null).
  const dock = readFileSync(new URL("../../Dock.qml", import.meta.url), "utf8")
  assert.doesNotMatch(dock, /property var taskStatus/, "Dock.qml must not keep a second task map")
  assert.match(dock, /readonly property var taskMap/, "Dock.qml must expose the one view readers use")
  assert.doesNotMatch(dock, /root\.taskStatus/, "nothing may write a local task map")

  const screen = readFileSync(new URL("../../components/logic/DockScreenLogic.qml", import.meta.url), "utf8")
  assert.doesNotMatch(screen, /root\.taskStatus =/, "the mirror's pull must be gone")

  const item = readFileSync(new URL("../../components/DockItem.qml", import.meta.url), "utf8")
  assert.match(item, /DockTasks\.taskStatusFor\(DockModel, root\.taskMap,/, "the tile must read the one view")

  // Every call site hands the task module the one identity owner: a call
  // without it would be a second matcher by omission (the functions throw).
  const root = new URL("../../", import.meta.url).pathname
  const call = /DockTasks\.(normalizeTaskStatus|withTaskStatus|clearTaskStatusFor|taskStatusFor)\(\s*([A-Za-z_$][\w$]*)?/g
  const offenders = []
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name)
      if (e.isDirectory()) {
        if (["tests", "node_modules", ".git", "experiment", "__pycache__"].includes(e.name)) continue
        walk(p)
        continue
      }
      if (!/\.(qml|js|mjs)$/.test(e.name)) continue
      const text = readFileSync(p, "utf8")
      for (const m of text.matchAll(call))
        if (m[2] !== "DockModel") offenders.push(`${p.slice(root.length)} calls DockTasks.${m[1]} with ${m[2] || "no id module"}`)
    }
  }
  walk(root)
  assert.deepEqual(offenders, [], offenders.join(", "))
})

test("the status look has one owner, and the hover chip reads it", () => {
  // The tile's badge (resolveBadgeView) and the hover chip (components/
  // DockItem.qml) are two surfaces describing one task. Before this rule each
  // carried its own copy of the status palette and its own copy of the chip's
  // label, so the badge and the chip could disagree about what a status looks
  // like. DockTasks.js is now the only file that spells a status colour.
  const root = new URL("../../", import.meta.url).pathname
  const palette = ["#f38ba8", "#89b4fa", "#a6e3a1"]
  const offenders = []
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name)
      if (e.isDirectory()) {
        // tests/ holds this assertion; experiment/ is the sibling worktree, a
        // second checkout of the same files.
        if (["tests", "node_modules", ".git", "experiment", "__pycache__"].includes(e.name)) continue
        walk(p)
        continue
      }
      if (!/\.(qml|js|mjs)$/.test(e.name) || e.name === "DockTasks.js") continue
      const text = readFileSync(p, "utf8")
      for (const hex of palette)
        if (text.includes(hex)) offenders.push(p.slice(root.length) + " spells " + hex)
    }
  }
  walk(root)
  assert.deepEqual(offenders, [], "a status colour is spelled outside DockTasks.js: " + offenders.join(", "))

  // The chip's two bindings go through the same owner the badge does.
  const item = readFileSync(new URL("../../components/DockItem.qml", import.meta.url), "utf8")
  assert.match(item, /DockTasks\.statusColor\(/, "the chip's dot must read DockTasks.statusColor")
  assert.match(item, /DockTasks\.chipLabel\(/, "the chip's text must read DockTasks.chipLabel")

  // An unknown status has no colour of its own: it must not borrow one, or the
  // chip could draw a healthy green dot for a status neither surface knows.
  assert.equal(M.statusColor(""), "transparent")
  assert.equal(M.statusGlyph(""), "")
  assert.equal(M.statusColor("running"), M.resolveBadgeView(0, { status: "running" }, false).color)
  assert.equal(M.statusColor("success"), M.resolveBadgeView(0, { status: "success" }, false).color)
  assert.equal(M.statusColor("error"), M.resolveBadgeView(0, { status: "error" }, false).color)

  // The chip's text is built by the same module, including its fallbacks.
  assert.equal(M.chipLabel({ status: "success", exitCode: 0, title: "cargo build", duration: 14 }),
    "cargo build (14s)")
  assert.equal(M.chipLabel({ status: "error", exitCode: 3, title: "cargo test", duration: 7 }),
    "cargo test (7s) [Exit 3]")
  assert.equal(M.chipLabel({ status: "running", exitCode: 0, title: "", duration: 0 }), "Task completed")
  assert.equal(M.chipLabel(null), "")
})

test("resolveBadgeView: priorities and states", () => {
  const errTask = { status: "error", exitCode: 1, title: "test", duration: 1 }
  const runTask = { status: "running", exitCode: 0, title: "test", duration: 0 }
  const okTask = { status: "success", exitCode: 0, title: "test", duration: 5 }

  // Error takes priority even if notifications exist
  const viewErr = M.resolveBadgeView(3, errTask, false)
  assert.equal(viewErr.mode, "status")
  assert.equal(viewErr.glyph, "!")
  assert.equal(viewErr.color, "#f38ba8")

  // Notifications take priority over success or running tasks
  const viewNotifOverOk = M.resolveBadgeView(3, okTask, false)
  assert.equal(viewNotifOverOk.mode, "count")
  assert.equal(viewNotifOverOk.count, 3)

  // Success task when no notifications
  const viewOk = M.resolveBadgeView(0, okTask, false)
  assert.equal(viewOk.mode, "status")
  assert.equal(viewOk.glyph, "✓")
  assert.equal(viewOk.color, "#a6e3a1")

  // Running task
  const viewRun = M.resolveBadgeView(0, runTask, false)
  assert.equal(viewRun.mode, "status")
  assert.equal(viewRun.glyph, "●")
  assert.equal(viewRun.color, "#89b4fa")

  // Active match does not suppress task status badge
  const viewActive = M.resolveBadgeView(0, okTask, true)
  assert.equal(viewActive.mode, "status")
  assert.equal(viewActive.glyph, "✓")

  // Active match does not clear error task until focused handler clears it
  const viewActiveError = M.resolveBadgeView(0, errTask, true)
  assert.equal(viewActiveError.mode, "status")
  assert.equal(viewActiveError.glyph, "!")

  // Empty state
  const viewEmpty = M.resolveBadgeView(0, null, false)
  assert.equal(viewEmpty.mode, "none")
  assert.equal(viewEmpty.count, 0)
})
