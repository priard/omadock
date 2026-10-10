# Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every element of the dock enters and leaves smoothly (row items, dividers, split panels, popups, window marks, badge), all motion comes from one source, and a setting picks Full / Reduced / Off.

**Architecture:** `DockMotion.js` turns the `animations` setting into one `root.motion` object (durations + flags) that every Behavior reads. `DockKeys.js` computes keyed-row diffs with a `leaving` state, applied by `KeyedListModel`, so a removed row stays while it animates out. `RowSlot.qml` wraps each row element and animates width/scale/opacity from `appear`. `PopupLife.qml` keeps popup windows alive through a fade of a frozen snapshot.

**Tech Stack:** QML (Qt 6.11, Quickshell 0.3.1), plain JS modules tested with `node --test` in a vm context, Python static tests (`unittest`), grim + PIL for live checks.

**Spec:** `docs/superpowers/specs/2026-10-11-animations-design.md`

## Global Constraints

- Levels: `full | reduced | off`, key `animations`, default `full`; not part of presets.
- Tokens: `fast` 120 ms, `base` 180 ms, `slow` 300 ms; Off → 0. Easing `Easing.OutCubic` entering, `Easing.InCubic` leaving.
- Flags per level — Full: `layout scale rise oneShots reveal fade` all true. Reduced: `fade` true, the rest false, durations kept. Off: every duration 0, every flag false.
- Extra tokens (ruling: the spec's "magnify as today"): `hover` 110 / 110 / 0 and `press` 90 / 90 / 0.
- `Dock.qml` ceiling 2412 lines (`tests/static/structure-check.py`); every other QML/JS file ≤ 800 lines; logic modules may not hold Timers/Repeaters/visual items; module functions take `root` first.
- Branch `feat/animations`, worktree `~/.local/share/omadock-wt/anim`. Never commit FORK.md, the manifest bump, `docs/superpowers/`, CLAUDE.md there.
- Live checkout = running desktop: merge into `priard` only after `git merge-tree --write-tree priard feat/animations >/dev/null` exits 0 (no pipe); then `omarchy restart shell`, `bash tests/smoke-test.sh`. No synthetic keyboard input, no clicks.
- No AI attribution; one topic per commit with a why-body.

## Review Focus

- A key that leaves and comes back before its exit ends (an app closing and reopening fast, a drive remounting): it must revive in place, not duplicate. Test in Task 3 (`revive`).
- Drag and drop while an item is leaving: insert indexes and the trailing drop gap must ignore leaving rows. Covered by Task 5 Step 4 (`liveItems`) and checked by hand.
- Startup and config reload: nothing should animate in at first sync (`initial`). Test in Task 3.
- Off: no Timer delay at all — a removed key disappears in the same turn. Test in Task 3 (`exitMs 0`) and live in Task 11.
- A popup reopened while its previous instance is fading: the new content must show, not the frozen image. Task 8 Step 3 handles `want` turning true during a fade.

---

### Task 0: Branch base

**Files:** none (git only)

Ruling (ledger it): the open PRs #51–#57 touch the same files (DockCard plate edges and label slots, AppGroupPopup, DockContextMenu, DockPopupWindow). Building on bare `upstream/experimental` would conflict with all of them. The branch is cut from `upstream/experimental` with those seven branches merged; the upstream PR is opened only after they land, rebased onto `experimental`.

- [ ] **Step 1:**

```bash
cd ~/.config/omarchy/plugins/omadock && git fetch upstream
git worktree add -b feat/animations ~/.local/share/omadock-wt/anim upstream/experimental
cd ~/.local/share/omadock-wt/anim
for b in feat/nested-plates feat/side-mark-size feat/spread-fixes feat/group-cell-hover feat/popup-grid feat/group-cell-menu feat/group-drag-fix; do
  git merge --no-edit $b || break
done
git status --short
```

Expected: one conflict in `components/DockCard.qml` (spread-fixes vs nested-plates, adjacent `spreadShift` / `plateEdges` lines): keep both — the `spreadShift` line without `+ row.spacing`, then the whole `plateEdges` property. `git add`, `git commit --no-edit`, continue the loop from the next branch.

- [ ] **Step 2:** `bash tests/run-all.sh 2>/dev/null | tail -1 || node --test tests/unit/*.test.mjs tests/unit/*.test.js | tail -3` — Expected: all pass. Write the ledger line.

### Task 1: `DockMotion.js`

**Files:**
- Create: `DockMotion.js`
- Test: `tests/unit/motion.test.mjs`
- Modify: `.github/workflows/ci.yml` (the `node --check` list gains `DockMotion.js`)

**Interfaces:**
- Produces: `DockMotion.normalizeLevel(v) -> "full"|"reduced"|"off"`; `DockMotion.plan(level) -> { level, fast, base, slow, hover, press, layout, scale, rise, oneShots, reveal, fade }`.

- [ ] **Step 1: Failing test** `tests/unit/motion.test.mjs`

```js
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
```

- [ ] **Step 2:** `node --test tests/unit/motion.test.mjs` — Expected: FAIL (`M.normalizeLevel is not a function`).

- [ ] **Step 3: Implement** `DockMotion.js`

```js
// The dock's animation policy (Settings → Motion & Effects → Animations):
// one plan every Behavior and effect reads (Dock.motion), so a level change
// reaches all of them and no file keeps its own idea of "fast". Plain JS with
// no Qt globals, so the node tests run it in a vm context like DockLabels.js.
//
// Timings: fast for fades and colours, base for layout, row items and
// popups, slow for the autohide slide; hover and press keep the magnifier's
// and the press dip's own short timings. Easing: OutCubic entering, InCubic
// leaving (callers pick by direction).
//
//   layout    widths and positions ease (row items, dividers, the card)
//   scale     entering and leaving elements scale (0.6 to 1)
//   rise      popups and tooltips rise a few pixels as they appear
//   oneShots  launch/urgent bounce, pulse, glow ripple, glitch
//   reveal    label typewriter / scramble
//   fade      opacity eases (Reduced keeps only this)

var LEVELS = ["full", "reduced", "off"]

function normalizeLevel(v) {
  var s = String(v === undefined || v === null ? "" : v).toLowerCase()
  return LEVELS.indexOf(s) >= 0 ? s : "full"
}

function plan(level) {
  var l = normalizeLevel(level)
  var on = l !== "off"
  var full = l === "full"
  return {
    level: l,
    fast: on ? 120 : 0, base: on ? 180 : 0, slow: on ? 300 : 0,
    hover: on ? 110 : 0, press: on ? 90 : 0,
    layout: full, scale: full, rise: full, oneShots: full, reveal: full,
    fade: on
  }
}
```

- [ ] **Step 4:** `node --test tests/unit/motion.test.mjs` — Expected: PASS (5). Add `&& node --check DockMotion.js` to the `node --check` line in `.github/workflows/ci.yml`.

- [ ] **Step 5: Commit** `feat(motion): one plan for every animation, by level` (body: why one owner — durations drifted 120/140/150/160/180, the new setting needs a single switch).

### Task 2: The setting

**Files:**
- Modify: `Dock.qml` (import, two properties; `dropParkSlot` body moves out), `components/logic/DockSlotLogic.qml` (gains `dropParkSlot(root, address)`), `components/logic/DockConfigLogic.qml` (read near `root.keepPointer =`, write near `conf.keepPointer =`), `components/settings/SettingsMotion.qml`, `SettingsSearch.js`, `README.md` (settings table + Motion section)

**Interfaces:**
- Consumes: `DockMotion.normalizeLevel`, `DockMotion.plan` (Task 1).
- Produces: `root.animations` (string), `root.motion` (plan object) — every later task reads `root.motion`.

- [ ] **Step 1: Make room in `Dock.qml`.** Move the body of `function dropParkSlot(address) { … }` (Dock.qml ~1875, 8 lines) into `DockSlotLogic.qml` as

```js
  // Forget one parked window's recorded place and its pending fix.
  function dropParkSlot(root, address) {
    if (!address || !root.parkSlots || root.parkSlots[address] === undefined) return
    var slots = {}
    for (var k in root.parkSlots) slots[k] = root.parkSlots[k]
    delete slots[address]
    root.parkSlots = slots
    root.pendingSlotFixes = (root.pendingSlotFixes || []).filter(function(a) { return a !== address })
  }
```

and leave in Dock.qml: `  function dropParkSlot(address) { return slotLogic.dropParkSlot(root, address) }`.

- [ ] **Step 2: Properties.** Add `import "DockMotion.js" as DockMotion` beside the other JS imports, and next to `property bool keepPointer: true`:

```qml
  property string animations: "full"      // full | reduced | off (DockMotion)
  readonly property var motion: DockMotion.plan(root.animations)
```

- [ ] **Step 3: Config.** In `DockConfigLogic` (read, beside `root.keepPointer = …`): `root.animations = DockMotion.normalizeLevel(parsed ? parsed.animations : "full")` with `import "../../DockMotion.js" as DockMotion` at the top; write: `conf.animations = root.animations`.

- [ ] **Step 4: Settings row** at the top of the Motion section in `SettingsMotion.qml`:

```qml
  ChoiceRow {
    key: "animations"
    label: "Animations"
    hint: "Reduced keeps short fades and drops movement and bounces. Off changes everything at once."
    options: [
      { value: "full", label: "Full" },
      { value: "reduced", label: "Reduced" },
      { value: "off", label: "Off" }
    ]
    value: root ? root.animations : "full"
    onPicked: function(v) { root.setOption("animations", v) }
  }
```

`SettingsSearch.js`: `{ key: "animations", page: "motion", label: "Animations", terms: ["motion", "reduce", "reduced", "off", "speed", "transitions"] },`. README: a row in the config table (`animations` | `string` | `"full"` | `"full"`, `"reduced"` or `"off"` …) and one sentence in the Motion settings section.

- [ ] **Step 5: Verify.** `python3 tests/static/structure-check.py` (Dock.qml ≤ 2412), `node --test tests/unit/*.test.mjs tests/unit/*.test.js`, `python3 -m unittest discover -s tests/unit -p 'test_*.py'`, `/usr/lib/qt6/bin/qmllint --silent Dock.qml components/settings/SettingsMotion.qml components/logic/DockConfigLogic.qml components/logic/DockSlotLogic.qml`. Live: merge into priard (merge-tree gate), restart, `omarchy-shell omadock openSettingsPage motion`, screenshot the settings window, `closeSettings`; set `"animations": "off"` in a config copy, `sleep 1.5`, restore — the dock must keep loading (smoke test).

- [ ] **Step 6: Commit** `feat(motion): Animations setting, Full / Reduced / Off` and, separately, `refactor(slots): dropParkSlot lives in DockSlotLogic` (first in order).

### Task 3: `DockKeys.js` — keyed rows with a leaving state

**Files:**
- Create: `DockKeys.js`
- Test: `tests/unit/keys.test.mjs`
- Modify: `.github/workflows/ci.yml` (`node --check DockKeys.js`)

**Interfaces:**
- Produces:
  - `DockKeys.target(rows, want, initial, now, exitMs) -> Array<{ key, leaving, fresh, slot, leaveAt }>`: `rows` = current rows (same shape, possibly empty), `want` = wanted keys in order. Wanted keys in `want` order; a row no longer wanted becomes `leaving: true` with `leaveAt = now + exitMs` (kept if already leaving), placed right after the row that preceded it before; a leaving key that is wanted again revives (`leaving: false`). `fresh` is true for a key not in `rows`, unless `initial`. `slot` counts non-leaving rows (leaving rows get the slot of the next live row, never used for layout). With `exitMs <= 0`, unwanted rows are dropped immediately.
  - `DockKeys.expire(rows, now) -> rows` without leaving rows whose `leaveAt <= now`, slots recomputed.
  - `DockKeys.nextExpiry(rows) -> number|-1` smallest `leaveAt` of leaving rows.
  - `DockKeys.tileKey(t)`, `folderKey(f)`, `driveKey(d) -> string`.

- [ ] **Step 1: Failing tests** `tests/unit/keys.test.mjs`

```js
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
  assert.deepEqual(keys(K.target(r0, ["b"], false, 5, 0)), ["b"])
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
```

- [ ] **Step 2:** `node --test tests/unit/keys.test.mjs` — Expected: FAIL (`K.target is not a function`).

- [ ] **Step 3: Implement** `DockKeys.js`

```js
// Keyed rows for the dock's Repeaters (KeyedListModel), with a leaving
// state: a key that is no longer wanted stays in the model, marked leaving,
// until its exit animation ends (DockMotion base), so its delegate can
// narrow and fade instead of vanishing in one frame. Plain JS, node-tested.

function _slots(rows) {
  var live = 0
  for (var i = 0; i < rows.length; i++) {
    rows[i].slot = live
    if (!rows[i].leaving) live++
  }
  return rows
}

function target(rows, want, initial, now, exitMs) {
  var prev = rows || []
  var wantList = want || []
  var wanted = {}
  for (var w = 0; w < wantList.length; w++) wanted[wantList[w]] = true
  var had = {}
  for (var p = 0; p < prev.length; p++) had[prev[p].key] = prev[p]
  var out = []
  for (var i = 0; i < wantList.length; i++) {
    var k = wantList[i]
    out.push({ key: k, leaving: false, fresh: !had[k] && !initial, slot: 0, leaveAt: 0 })
  }
  if (exitMs > 0) {
    // Keep each unwanted row after the row that preceded it before.
    for (var j = 0; j < prev.length; j++) {
      var r = prev[j]
      if (wanted[r.key]) continue
      var at = 0
      for (var b = j - 1; b >= 0; b--) {
        var idx = -1
        for (var o = 0; o < out.length; o++) if (out[o].key === prev[b].key) { idx = o; break }
        if (idx >= 0) { at = idx + 1; break }
      }
      out.splice(at, 0, { key: r.key, leaving: true, fresh: false, slot: 0,
        leaveAt: r.leaving ? r.leaveAt : now + exitMs })
    }
  }
  return _slots(out)
}

function expire(rows, now) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var r = rows[i]
    if (r.leaving && r.leaveAt <= now) continue
    out.push({ key: r.key, leaving: r.leaving, fresh: r.fresh, slot: 0, leaveAt: r.leaveAt })
  }
  return _slots(out)
}

function nextExpiry(rows) {
  var best = -1
  for (var i = 0; i < (rows || []).length; i++)
    if (rows[i].leaving && (best < 0 || rows[i].leaveAt < best)) best = rows[i].leaveAt
  return best
}

function tileKey(t) { return t && t.type === "group" ? "app:" + t.appId : "win:" + (t && t.win ? t.win.address : "") }
function folderKey(f) { return f && f.command ? "cmd:" + (f.name || "") + ":" + f.command : "path:" + (f ? f.path : "") }
function driveKey(d) { return "dev:" + (d ? d.dev : "") }
```

- [ ] **Step 4:** `node --test tests/unit/keys.test.mjs` — Expected: PASS (8). Add `node --check DockKeys.js` to CI.
- [ ] **Step 5: Commit** `feat(motion): keyed rows that leave before they go`.

### Task 4: `KeyedListModel` applies the rows

**Files:**
- Modify: `components/KeyedListModel.qml`

**Interfaces:**
- Consumes: `DockKeys.target/expire/nextExpiry` (Task 3), `root.motion.base` (Task 2).
- Produces: model roles `key`, `leaving`, `fresh`, `slot`; properties `liveCount` (int), `exitMs` (int, set by DockCard from `root.motion.base`); `sync(keys)` unchanged signature.

- [ ] **Step 1: Rewrite** `KeyedListModel.qml`

```qml
import QtQuick
import "../DockKeys.js" as DockKeys

// A ListModel of string keys kept in step with a list by moves, inserts and
// per-row updates. A Repeater over a plain JS array rebuilds every delegate
// whenever the array is replaced; over this model the delegates of keys that
// stay are kept, and they look their data up by key. A key that goes away
// stays for exitMs, marked leaving, so its delegate can animate out
// (DockKeys.target); the first sync marks nothing fresh.
ListModel {
  id: model

  property int exitMs: 0
  property int liveCount: 0
  property var _rows: []
  property bool _synced: false

  property Timer _expiry: Timer {
    onTriggered: model._apply(DockKeys.expire(model._rows, Date.now()))
  }

  function sync(keys) {
    model._apply(DockKeys.target(model._rows, keys || [], !model._synced, Date.now(), model.exitMs))
    model._synced = true
  }

  function _apply(rows) {
    // Remove what is gone, then move/insert into order, then update roles.
    var keep = {}
    for (var i = 0; i < rows.length; i++) keep[rows[i].key] = true
    for (var r = model.count - 1; r >= 0; r--) if (!keep[model.get(r).key]) model.remove(r)
    for (var j = 0; j < rows.length; j++) {
      var row = rows[j]
      if (!(j < model.count && model.get(j).key === row.key)) {
        var at = -1
        for (var k = j + 1; k < model.count; k++) if (model.get(k).key === row.key) { at = k; break }
        if (at >= 0) model.move(at, j, 1)
        else model.insert(j, { key: row.key, leaving: row.leaving, fresh: row.fresh, slot: row.slot })
      }
      if (model.get(j).leaving !== row.leaving) model.setProperty(j, "leaving", row.leaving)
      if (model.get(j).slot !== row.slot) model.setProperty(j, "slot", row.slot)
    }
    model._rows = rows
    var live = 0
    for (var c = 0; c < rows.length; c++) if (!rows[c].leaving) live++
    model.liveCount = live
    var next = DockKeys.nextExpiry(rows)
    if (next < 0) model._expiry.stop()
    else { model._expiry.interval = Math.max(1, next - Date.now()); model._expiry.restart() }
  }
}
```

Note (`fresh` is set only on insert: a delegate reads it once at creation).

- [ ] **Step 2: Wire `exitMs`** in `DockCard.qml`: on `pinnedRowModel` and `runningModel` add `exitMs: cardWrapper.root ? cardWrapper.root.motion.base : 0`.
- [ ] **Step 3: Verify** `qmllint` on the file; merge into priard (gate), restart, smoke test, `journalctl --user --since "-30 s" | grep -iE "omadock/"` — Expected: clean; the dock behaves as before (delegates do not use the roles yet; a closed app now lingers 180 ms invisible-change-free, then goes).
- [ ] **Step 4: Commit** `feat(motion): KeyedListModel keeps leaving rows until their exit ends`.

### Task 5: `RowSlot.qml` and the app rows

**Files:**
- Create: `components/RowSlot.qml`
- Modify: `components/DockCard.qml` (Omarchy button, pinned row delegate, running delegate, `liveItems`, trailing DropGap), `components/logic/DockDragLogic.qml`, `components/logic/DockContextLogic.qml` (itemGeometry)

**Interfaces:**
- Consumes: model roles from Task 4, `root.motion`.
- Produces: `RowSlot { rootRef, fresh, leaving, shown, default content; readonly child }`; `cardWrapper.liveItems(repeater) -> Array<Item>` (the row elements of live rows, in order).

- [ ] **Step 1: Create** `components/RowSlot.qml`

```qml
import QtQuick

// One element of the dock's row as it enters and leaves (DockMotion). The
// slot is as wide as its element times `appear`, so the neighbours and the
// card ease along; the element scales up from 0.6 and fades in with it.
// Repeater rows set `fresh` and `leaving` (KeyedListModel); a single element
// (the Omarchy button) sets `shown`. Reduced keeps only the fade (the width
// snaps); Off changes at once.
Item {
  id: slot

  property var rootRef: null
  readonly property var root: rootRef
  readonly property var motion: root ? root.motion : null
  property bool fresh: false
  property bool leaving: false
  property bool shown: true
  readonly property bool wanted: slot.shown && !slot.leaving

  default property alias content: holder.data
  readonly property Item child: holder.children.length > 0 ? holder.children[0] : null

  property real appear: (slot.fresh || !slot.wanted) ? 0 : 1
  Behavior on appear {
    enabled: !!slot.motion && slot.motion.base > 0
    NumberAnimation {
      duration: slot.motion ? slot.motion.base : 0
      easing.type: slot.wanted ? Easing.OutCubic : Easing.InCubic
    }
  }
  Component.onCompleted: slot.appear = slot.wanted ? 1 : 0
  onWantedChanged: slot.appear = slot.wanted ? 1 : 0

  readonly property real full: slot.child ? slot.child.width : 0
  width: (slot.motion && slot.motion.layout) ? slot.full * slot.appear : (slot.appear > 0.001 ? slot.full : 0)
  height: slot.child ? slot.child.height : 0
  visible: slot.appear > 0.001
  z: slot.child ? slot.child.z : 0

  Item {
    id: holder
    width: slot.full
    height: slot.height
    x: Math.round((slot.width - slot.full) / 2)
    opacity: slot.appear
    scale: (slot.motion && slot.motion.scale) ? 0.6 + 0.4 * slot.appear : 1
    transformOrigin: Item.Bottom
  }
}
```

- [ ] **Step 2: Wrap the delegates in `DockCard.qml`.**
  - Omarchy button: `RowSlot { rootRef: cardWrapper.rootRef; shown: root ? root.showAppsButton : true; DockIconButton { …existing body without its `visible:` line… } }`.
  - Pinned row: the delegate becomes `RowSlot { id: rowSlotWrap; required property string key; required property int index; required property bool leaving; required property bool fresh; required property int slot; rootRef: cardWrapper.rootRef; Loader { id: rowSlot; …existing… } }`. Inside the Loader replace every `rowSlot.index` / `index` used for layout (`home`, `labelSlot`, `dropLineHere`) with `rowSlotWrap.slot`; `key` reads `rowSlotWrap.key`.
  - Running: delegate `RowSlot { id: runWrap; required property string key; required property int index; required property bool leaving; required property bool fresh; required property int slot; rootRef: cardWrapper.rootRef; shown: !runningDockItem.isFullyTiled; DockItem { id: runningDockItem; …existing, `key` → runWrap.key, remove `visible: !isFullyTiled`… } }` (`visibleRunningSlotBefore(index)` keeps using `runWrap.index`: it counts data rows, and leaving rows are not in `runningSection`). Ruling to ledger: a fully-tiled app now animates out of the running run too (it uses `shown`).
  - Trailing pinned `DropGap.open`: compare with `pinnedRowModel.liveCount` instead of `pinnedRowRepeater.count`.

- [ ] **Step 3: `liveItems`** in `DockCard.qml`:

```qml
  // The row elements of a Repeater's live rows (not leaving), in order: the
  // drag logic and itemGeometry measure these, never a row on its way out.
  function liveItems(repeater) {
    var out = []
    for (var i = 0; i < repeater.count; i++) {
      var s = repeater.itemAt(i)
      if (!s || s.leaving || (s.shown === false)) continue
      var it = s.child !== undefined ? s.child : s
      if (it && it.item !== undefined && it.sourceComponent !== undefined) it = it.item   // Loader
      if (it) out.push(it)
    }
    return out
  }
```

- [ ] **Step 4: Callers.** In `DockDragLogic.qml` (lines ~21–35, ~50–52, ~75–130, ~211–213) and `DockContextLogic.itemGeometry` (~160–180) replace `card.X.count` / `card.X.itemAt(i)` (and `.item` on pinned slots) with `var items = card.liveItems(card.X)` + `items.length` / `items[i]`. Positions: the drag logic compares pointer x with item x in row coordinates — use `items[i].mapToItem(card.row, 0, 0).x` where it used `slot.x` (the element now sits inside its RowSlot). Folder/drive repeaters are converted in Task 6; leave their call sites for then.
- [ ] **Step 5: Verify.** qmllint on the changed files, unit + static tests, structure-check. Merge into priard (gate), restart, smoke. Live: `tests/live/layout.sh`; then the entry/exit probe:

```bash
S=/tmp/claude-1000/-home-priard--config-omarchy-plugins-omadock/bc14d2d2-802e-45ac-9cb1-a1c788887c29/scratchpad; CFG=~/.config/omarchy/omadock.json; cp $CFG $S/cfg.bak
python3 -c "import json;p='$CFG';c=json.load(open(p));c['showAppsButton']=False;json.dump(c,open(p,'w'),indent=2)"
for i in $(seq 0 11); do omarchy-shell omadock itemGeometry > $S/g$i.json; sleep 0.03; done
cp $S/cfg.bak $CFG
```

Expected: the first item's x moves over several samples (not one step) at Full. Repeat with `"animations": "off"` in the edit: one step. Restore the config.
- [ ] **Step 6: Commit** `feat(motion): apps, groups and the Omarchy button ease in and out of the row` (body: RowSlot, slot role, liveItems; why).

### Task 6: Tiles, folders/buttons, drives

**Files:**
- Create: `components/DockRightGroup.qml` (the `rightRow` Row: folder divider, folders/buttons Repeater, trailing DropGap and DropGhost, drive divider, drives Repeater — moved verbatim from DockCard, then converted)
- Modify: `components/DockCard.qml` (tiles Repeater; `rightRow` replaced by `DockRightGroup { id: rightRow; … }` keeping `rightRowRef`, `folderSeparatorRef`, `foldersRepeater`, `drivesRepeater` aliases), `components/logic/DockDragLogic.qml`, `components/logic/DockContextLogic.qml`

**Interfaces:**
- Consumes: `DockKeys.tileKey/folderKey/driveKey`, `KeyedListModel`, `RowSlot`, `liveItems`.
- Produces: `DockRightGroup` exposes `foldersRepeater`, `drivesRepeater`, `folderSeparator`, `driveSeparator`, `trailingDropGap` as aliases; DockCard re-exposes them under the old names so `card.foldersRepeater` etc. still work.

- [ ] **Step 1: Extract `DockRightGroup.qml`** (verbatim move, `root`/`dockCard`/`cardWrapper`/`row` passed in as properties: `rootRef`, `cardRef`, `wrapperRef`, `outerRow`), DockCard keeps `id: rightRow` on the instance. Verify layout unchanged: `tests/live/layout.sh` passes, `itemGeometry` identical before/after (diff the JSON). Commit `refactor(card): the right group in its own component` (DockCard under 800 lines for what follows).
- [ ] **Step 2: Keyed models.** In DockCard: `KeyedListModel { id: tileRowModel; exitMs: … }`; `readonly property var tileByKey` (map from `DockKeys.tileKey` over `root.tileModel`); `Connections` on `root.tileModelChanged` → `tileRowModel.sync(root.tileModel.map(DockKeys.tileKey))`. Same in DockRightGroup for folders/buttons (`root.pinnedFolders.concat(root.pinnedButtons)`, `DockKeys.folderKey`) and drives (`root.mountedDrives`, `DockKeys.driveKey`), with `…ByKey` maps. Delegates become `RowSlot` with `required` roles, the inner item reading its data through `Binding on modelData { value: byKey[key]; when: !!byKey[key]; restoreMode: Binding.RestoreNone }` (same pattern as the pinned run) and using `slot` where they used `index` (`tileIndex`, `slotIndex`, `labelSlot`, `homeCenter`, `dropLineHere`). Folder count comparisons (`foldersRepeater.count` in the trailing DropGap and DropGhost) use `folderRowModel.liveCount`.
- [ ] **Step 3: Callers** in DockDragLogic (`foldersRepeater` lines ~21–35, ~211–213) and itemGeometry (tiles, folders, drives) switch to `card.liveItems(…)` as in Task 5.
- [ ] **Step 4: Verify** as Task 5 Step 5 plus: pin a folder through IPC/config (`pinnedFolders` + one entry, restore after) and capture the itemGeometry burst — the folders ease. qmllint, tests, structure-check.
- [ ] **Step 5: Commit** `feat(motion): tiles, folders, buttons and drives ease in and out`.

### Task 7: Dividers and split panels

**Files:**
- Create: `components/RowDivider.qml` (the four identical divider Items, with the line)
- Modify: `components/DockCard.qml`, `components/DockRightGroup.qml`

**Interfaces:**
- Produces: `RowDivider { rootRef, cardRef, outerY, shown, lineHidden }` — `width` animates `shown ? root.separatorWidth : 0` when `motion.layout`; `visible: width > 0.5`; the line rectangle exactly as today (`y` from `cardRef.dividerTop - outerY - y` for long dividers).

- [ ] **Step 1: Create `RowDivider.qml`** from the existing divider block (DockCard ~484–504) with:

```qml
  property bool shown: false
  readonly property var motion: root ? root.motion : null
  width: shown ? (root ? root.separatorWidth : Style.space(1)) : 0
  Behavior on width {
    enabled: !!divider.motion && divider.motion.layout
    NumberAnimation { duration: divider.motion ? divider.motion.base : 0; easing.type: divider.shown ? Easing.OutCubic : Easing.InCubic }
  }
  visible: width > 0.5
  opacity: shown ? 1 : 0
  Behavior on opacity { enabled: !!divider.motion && divider.motion.fade; NumberAnimation { duration: divider.motion ? divider.motion.fast : 0 } }
```

- [ ] **Step 2: Replace** `leftTileSeparator`, `separator` (DockCard) and `folderSeparator`, `driveSeparator` (DockRightGroup) with `RowDivider { id: …; shown: root.hasLeftTileSeparator / hasSeparator / hasFolderSeparator / hasDriveSeparator; lineHidden: … }` keeping the ids. `segments` cuts test `separator.visible` etc. — keep; a panel now narrows with its divider's width.
- [ ] **Step 3: Verify**: with `splitSections: true`, empty `pinnedFolders` and `pinnedButtons` in a config copy (the folder divider and the right panel go) and capture a grim burst right after the write (`for i in $(seq 8); do grim -o DP-1 $S/f$i.png; done`): at Full the right panel's width shrinks across frames instead of disappearing in one; restore the config (the folders come back, the panel grows).
- [ ] **Step 4: Commit** `feat(motion): dividers and split panels narrow instead of vanishing`.

### Task 8: Popups fade and rise

**Files:**
- Create: `components/PopupLife.qml`
- Modify: `components/DockPopupWindow.qml`, `Dock.qml` (three `PopupLife` lines, the three `LazyLoader.active` lines), `components/FolderPopup.qml`, `components/AppGroupPopup.qml` (drop their dead `Behavior on opacity`)

**Interfaces:**
- Produces: `PopupLife { dockRoot, want; readonly alive, level, closing }`; `DockPopupWindow.life` (a PopupLife).

- [ ] **Step 1: `PopupLife.qml`**

```qml
import QtQuick

// The life of one dock popup (menu, folder stack, opened group), like
// TooltipLife: `want` is the caller's open condition; `alive` keeps the
// popup's window until the fade-out ends; `closing` tells the window to show
// its frozen last frame (the menu's own state clears the moment it closes).
QtObject {
  id: life
  property var dockRoot: null
  property bool want: false
  readonly property var motion: dockRoot ? dockRoot.motion : null
  property bool alive: false
  property real level: 0
  readonly property bool closing: alive && !want
  property Behavior _fade: Behavior on level {
    NumberAnimation { duration: life.motion ? life.motion.base : 0; easing.type: life.want ? Easing.OutCubic : Easing.InCubic }
  }
  onWantChanged: {
    if (life.want) { life.alive = true; life.level = 1 }
    else if (!life.motion || life.motion.base <= 0) { life.level = 0; life.alive = false }
    else life.level = 0
  }
  onLevelChanged: if (life.level === 0 && !life.want) life.alive = false
}
```

(If a `Behavior` cannot live on a QtObject, make PopupLife an `Item { width: 0; height: 0 }` like TooltipLife; ledger the ruling.)

- [ ] **Step 2: Dock.qml.** Next to each LazyLoader (inside the same parent, one line each):

```qml
    PopupLife { id: stackLife; dockRoot: root; want: root.activeStackFolder !== "" && root.dockVisible }
```

`groupLife` (`root.activeAppGroupId !== "" && root.dockVisible`), `contextLife` (`root.contextAppId !== ""`). Each loader: `active: stackLife.alive` / `groupLife.alive` / `contextLife.alive`, and its `DockPopupWindow` gets `life: stackLife` (etc.). structure-check: Dock.qml ≤ 2412.
- [ ] **Step 3: DockPopupWindow.** Add `property var life: null`. The body draws through a snapshot while closing:

```qml
  // While closing, the menu's state is already gone: the last frame fades.
  ShaderEffectSource {
    id: frozen
    sourceItem: popup.body
    live: !(popup.life && popup.life.closing)
    hideSource: !!(popup.life && popup.life.closing)
    visible: !!(popup.life && popup.life.closing)
    x: lastX; y: lastY; width: lastW; height: lastH
    property real lastX: 0; property real lastY: 0; property real lastW: 0; property real lastH: 0
  }
  Binding { target: frozen; property: "lastX"; value: popup.body ? popup.body.x : 0; when: !(popup.life && popup.life.closing) }
  Binding { target: frozen; property: "lastY"; value: popup.body ? popup.body.y : 0; when: !(popup.life && popup.life.closing) }
  Binding { target: frozen; property: "lastW"; value: popup.body ? popup.body.width : 0; when: !(popup.life && popup.life.closing) }
  Binding { target: frozen; property: "lastH"; value: popup.body ? popup.body.height : 0; when: !(popup.life && popup.life.closing) }
```

and on the window's `contentItem`: `opacity: popup.life ? popup.life.level : 1` and a `transform: Translate { y: (popup.life && popup.dockRoot && popup.dockRoot.motion.rise) ? (1 - popup.life.level) * Style.space(6) : 0 }`. Input mask: `mask: Region { item: (popup.life && popup.life.closing) ? null : popup.body }`. The focus grab `active: popup.visible && !(popup.life && popup.life.closing)`. Reopen during a fade: `want` true → `closing` false → `live` true again, the new body shows (Review Focus).
- [ ] **Step 4: Verify.** qmllint; merge (gate), restart; with a temporary `debugMenu`/close IPC pair in DockHost (as in the PR #55 screenshots), capture grim frames right after close at Full: the menu is still there, partly transparent, for ~180 ms; at Off: gone in the first frame. Remove the debug function, grep it is gone.
- [ ] **Step 5: Commit** `feat(motion): menus and popups fade and rise in and out`.

### Task 9: Window marks and the badge

**Files:**
- Modify: `components/DockIndicatorRow.qml`, `components/DockIndicator.qml` (no new behaviour, durations only), `components/BadgeMark.qml`

- [ ] **Step 1: Marks.** In DockIndicatorRow add

```qml
  readonly property var motion: marks.root ? marks.root.motion : null
  // A mark that goes stays one exit long (it shrinks and fades); new marks
  // grow from nothing.
  property int shownDots: marks.plan.dots
  Timer { id: dotsLater; interval: marks.motion ? marks.motion.base : 0; onTriggered: marks.shownDots = marks.plan.dots }
  Connections {
    target: marks
    function onPlanChanged() {
      if (marks.plan.dots >= marks.shownDots || !marks.motion || marks.motion.base <= 0) { dotsLater.stop(); marks.shownDots = marks.plan.dots }
      else dotsLater.restart()
    }
  }
```

The Grid's `columns`/`rows` use `Math.max(marks.plan.slots, marks.shownDots + (marks.plan.overflow ? 1 : 0))`; the Repeater's model is `marks.shownDots`; each cell gets `readonly property bool going: index >= marks.plan.dots` and `property real appear: 0` with `Component.onCompleted: appear = 1`, `onGoingChanged: appear = going ? 0 : 1`, a Behavior (`motion.base`, gated by `motion.fade`), and `opacity: appear; scale: (marks.motion && marks.motion.scale) ? 0.4 + 0.6 * appear : 1`. Keep the pixel-grid placement untouched (scale is a transform). `visible: marks.running` stays.
- [ ] **Step 2: Badge.** In BadgeMark: `property int shownCount: 0` updated in `onCountChanged: if (count > 0) shownCount = count` (and `Component.onCompleted`), `property real level: count > 0 ? 1 : 0` with a Behavior (`motion.base`, OutCubic/InCubic by direction, enabled when `motion.fade`), `visible: level > 0.01 && anchorRef !== null`, `opacity: level`, `scale: motion.scale ? 0.5 + 0.5 * level : 1`, text uses `shownCount`, `Behavior on width { enabled: motion.layout; NumberAnimation { duration: motion.fast } }`. Keep x/y placement (it reads `width`).
- [ ] **Step 3: Verify** live: badge with the temporary `debugGroup`-style IPC that sets `notificationBadges` then clears it, grim burst: the badge shrinks/fades. Marks: `tests/live/indicators.sh` — ask the user before running (it opens terminal windows); otherwise check by eye on the next window open.
- [ ] **Step 4: Commit** `feat(motion): window marks and the badge grow and fade`.

### Task 10: One-shots, labels, autohide, every duration from motion

**Files:**
- Modify: `components/DockItem.qml`, `components/HoverFx.qml`, `components/DockLabel.qml`, `components/DockCard.qml` (autohide), `components/DockIconArt.qml`, `components/DockAppGroupItem.qml`, `components/DockFolderItem.qml`, `components/DockDriveItem.qml`, `components/DockIconButton.qml`, `components/PreviewTile.qml`, `components/TilePlate.qml`, `components/TooltipLife.qml`, `components/WindowCardStack.qml`, `components/DropGap.qml`, `components/AppGroupPopup.qml`, `components/DockIndicator.qml`, `Dock.qml` (reveal strip, 3 lines in place)
- Create test: `tests/unit/test_motion_durations.py`

- [ ] **Step 1: Failing static test** `tests/unit/test_motion_durations.py`

```python
"""Every animation duration in the dock's QML comes from the motion plan.

A literal duration ignores the Animations setting (Reduced / Off). The
effects that are animations themselves keep their own timings and are
listed here; they are gated by motion.oneShots / motion.reveal instead."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
LITERAL = re.compile(r"duration:\s*[\d(]")
ALLOWED = {
    # launch / urgent bounce and pulse (oneShots)
    ("components/DockItem.qml", "from: 1.0; to: 0.35; duration: 650"),
    ("components/DockItem.qml", "from: 0.35; to: 1.0; duration: 650"),
    ("components/DockItem.qml", "to: -Style.space(13); duration: 260"),
    ("components/DockItem.qml", "to: 0; duration: 260"),
    ("components/DockItem.qml", "PauseAnimation { duration: item.urgent ? 380 : 220 }"),
    # drop-target halo (oneShots)
    ("components/DockItem.qml", "from: 0.5; to: 1.0; duration: 350"),
    ("components/DockItem.qml", "from: 1.0; to: 0.5; duration: 350"),
    ("components/DockAppGroupItem.qml", "from: 0.5; to: 1.0; duration: 350"),
    ("components/DockAppGroupItem.qml", "from: 1.0; to: 0.5; duration: 350"),
    # glow ripple, glitch burst (oneShots)
    ("components/HoverFx.qml", "property: \"ring\""),
    ("components/HoverFx.qml", "property: \"glitchT\""),
    # label typewriter / erase (reveal)
    ("components/DockLabel.qml", "duration: Math.min(300, 25 *"),
    ("components/DockLabel.qml", "id: eraseAnim"),
}


def literals():
    found = []
    for path in [ROOT / "Dock.qml", *sorted((ROOT / "components").glob("*.qml"))]:
        rel = str(path.relative_to(ROOT))
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if LITERAL.search(line) and not any(rel == f and frag in line for f, frag in ALLOWED):
                found.append(f"{rel}:{n}: {line.strip()}")
    return found


class MotionDurations(unittest.TestCase):
    def test_durations_come_from_motion(self):
        self.assertEqual(literals(), [])


if __name__ == "__main__":
    unittest.main()
```

`python3 -m unittest tests.unit.test_motion_durations` — Expected: FAIL listing ~35 lines.

- [ ] **Step 2: Convert durations.** Each component already reaches `root` (or `dockRoot` / `life.dockRoot` / `fx.hoverFx` owner); add `readonly property var motion: root ? root.motion : null` where missing and map:
  - 110 OutQuad magnify (DockItem, DockAppGroupItem, DockFolderItem, DockDriveItem, DockIconButton, PreviewTile) → `motion.hover`.
  - 90 press (DockItem:233) → `motion.press`.
  - 120 fades/colours (DockItem drag opacity, DockIndicator colours, DockIconButton colour, TooltipLife `fadeMs` default bound to `motion.fast`, WindowCardStack frontAspect, AppGroupPopup cell 100s) → `motion.fast`, easing OutCubic.
  - 140 indicator size (DockIndicator:120–121) → `motion.fast` OutCubic.
  - 160 (DropGap, DockFolderItem ghostWidth, HoverFx hoverLevel, TilePlate, DockLabel hoverLevel, DockCard trailing DropGhost) → `motion.base`.
  - 180 (DockLabel progress, marksLevel, WindowCardStack y/scale/opacity) → `motion.base`.
  - DockIconArt revealLevel 450 → `motion.slow`.
  - Autohide (DockCard:122, :130): slide `motion.slow` in / `motion.slow` out with `enabled: motion.layout` on the bottomMargin Behavior; opacity `motion.base` both ways (gated by `motion.fade`).
  - Dock.qml reveal strip (2284, 2290, 2291): `root.motion.slow`, `root.motion.fast`, `root.motion.fast` — edit in place, no new lines.
- [ ] **Step 3: Gate the one-shots.**
  - DockItem: `bouncing` requires `root.motion.oneShots`; `SequentialAnimation on bounceY` gets `alwaysRunToEnd: true` and the `onBouncingChanged` reset line goes (the hop finishes, then rests at 0). `SequentialAnimation on pulse` → `running: item.pulsing && dockVisible && root.motion.oneShots`, `alwaysRunToEnd: true`; keep `onPulsingChanged: if (!item.pulsing) item.pulse = 1.0` only when `!motion.oneShots` (so Off never leaves the icon half-faded).
  - Drop-target halos (DockItem ~250, DockAppGroupItem ~218): run only when `motion.oneShots`.
  - HoverFx: `ringAnim.restart()` / `glitchAnim.restart()` only when `fx.motion && fx.motion.oneShots` (HoverFx gets `property var motion: null`, set by DockIconArt / callers from `root.motion`).
  - DockLabel: typewriter/scramble only when `root.motion.reveal`; otherwise `revealT` jumps to 1 (whole name).
- [ ] **Step 4:** `python3 -m unittest tests.unit.test_motion_durations` — Expected: PASS. Full unit suite, qmllint on all changed files, structure-check.
- [ ] **Step 5: Live:** merge (gate), restart, smoke; with `launchBounce` on, `omarchy-shell omadock` has no launch IPC — check by eye later; check Off: the reveal strip, autohide (set `autohide: true` in a config copy, move the pointer away from the dock: `hyprctl dispatch 'hl.dsp.cursor.move({x=2560, y=700})'`, grim after 50 ms: the dock is already hidden; restore pointer and config).
- [ ] **Step 6: Commit** `feat(motion): one-shots, label reveal and autohide follow the setting` and `refactor(motion): every duration comes from the motion plan` (two commits: gating first, then the mechanical conversion + test).

### Task 11: Wrap-up

- [ ] **Step 1:** In the worktree: the CI-equivalent script (`node --check` list incl. DockMotion.js and DockKeys.js, node tests, `py_compile`, unittest, security-grep, structure-check, `qmllint --silent` CI set, shaders-in-sync, manifest-check) — Expected: all OK.
- [ ] **Step 2:** Live matrix at Full, Reduced, Off (config copy, restore after): Omarchy button toggle (itemGeometry burst), folder add/remove, split panel narrowing, context menu close (debug IPC, removed afterwards), badge — record per level whether it eases, fades only, or snaps. Off must snap everywhere.
- [ ] **Step 3:** Merge into priard (gate), restart, smoke, `bash tests/run-all.sh`; bump `manifest.json` to the next `-priard.N`; FORK.md "Not upstream yet: feat/animations (waits for #51–#57)"; push `fork priard feat/animations`.
- [ ] **Step 4:** Final whole-branch review (fresh reviewer, most capable model) with this plan's Review Focus; fix Critical/Important with a failing test first.
- [ ] **Step 5:** Hand over to the user: clicks and drags during animations, pin/unpin, group create/ungroup, minimize to tiles, drives, popups reopened quickly, each level. No upstream PR until #51–#57 land and the user says go.
