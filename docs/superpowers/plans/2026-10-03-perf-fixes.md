# Perf Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the dock's CPU per event and keep idle CPU at zero in every state (upstream PR `feat/perf-fixes`), measured against the baseline benchmark.

**Architecture:** Small, independent fixes on branch `feat/perf-fixes` cut from `upstream/main` in the worktree `~/.local/share/omadock-wt/perf`. Pure logic moves into `DockModel.js` with `node:test` tests; QML-only fixes are verified live after one merge into `priard` (Task 6), where the benchmark compares before and after.

**Tech Stack:** QML (Quickshell 0.3.1), `DockModel.js` + `node --test`, the fork benchmark `tests/bench/bench.py`.

**Spec:** `docs/superpowers/specs/2026-10-02-performance-design.md` (section B, `feat/perf-fixes`)

## Global Constraints

- Code changes happen only in the worktree `~/.local/share/omadock-wt/perf` (branch `feat/perf-fixes`, from `upstream/main`). The live checkout `~/.config/omarchy/plugins/omadock` (`priard`) only receives the finished branch through a merge in a temporary worktree followed by `git merge --ff-only` (same procedure as `feat/hardening`; `saveConfig`/presets regions conflict).
- Plugin hot reload does not load edited QML reliably: after any QML change in the live checkout, run `omarchy restart shell; sleep 8; bash tests/smoke-test.sh`.
- Any file written inside the live plugin directory reloads the dock for ~0.5 s; keep scratch files in the session scratchpad and run Python with `PYTHONDONTWRITEBYTECODE=1`.
- No clicks, no keyboard input. Pointer moves and `hyprctl dispatch` workspace switches are allowed during measurements; notify-send from a non-focused app is allowed to create an urgent state (Task 6) — tell the user it will leave that app's icon marked urgent until they focus it.
- English in code and commits, no AI attribution, one topic per commit with a why.
- Opening the upstream PR needs the user's go-ahead (they gave a general "open PR" for #23; ask again for this one with the numbers).

## Evidence (measured while planning, 2026-10-03)

- A workspace switch triggers one `refreshDock()` of 3–4 ms (probe in `refreshDock`, 6 switches), out of ~26 ms quickshell CPU per switch (baseline S5). Workspace switches do not change any window's workspace, so the rebuilt model equals the old one, but assigning it re-evaluates every delegate binding.
- The icon index scan produces 23 589 lines (2 299 unique names) in 0.11 s; every line is one JS callback on the GUI thread (`SplitParser`), on start and on every theme change.
- `handleThemeChanged` has five triggers (3 `Color` signals, 2 watched files); each runs `appLibrary.refreshIcons()` + `rescanApps()` + `refreshDock()` synchronously.
- Urgent bounce and pulse are `loops: Animation.Infinite` while `urgent && dockVisible`; with autohide off that is forever. The indicator keeps `Color.urgent` independently of the animation, so a static hint remains when the animation stops.
- `closewindow` calls `refreshDock()` synchronously and also restarts `modelTimer` (40 ms), so every close rebuilds twice.
- `DockCard.qml:454` shadow segments keep `layer.enabled: true` while invisible (`showShadow` off).

## Rulings against the spec (made while planning)

- **Spec items 5 (entryFor cache), 7 (MPRIS map), 9 (per-icon shadow), 10 (FileTile) are deferred.** `entryFor` runs only in click handlers on `upstream/main` (not in the rebuild); the MPRIS check, per-icon shadow and FileTile costs only apply in configurations the user does not use and have no measurement behind them. Doing them now would add risk to an upstream PR without evidence.
- **Spec item 3 is solved by an equality check** instead of special-casing workspace events: `refreshDock` skips the assignment when the rebuilt model equals the current one. This covers workspace switches and every other event that changes nothing, and keeps the existing rebuild triggers (and the Hyprland-handle-lag safeguards) intact.
- **Spec item 11 (preview capture cap) belongs to PR #22**, not this branch; it stays as a follow-up.
- **QML-only fixes are verified live, not unit-tested** (Tasks 4–5): there is no QML test runner for this plugin; Task 6 measures each with the benchmark or a targeted probe before and after.

## Review Focus

- A model that differs only inside `windowList` (a title change, a window moving workspace) must still be assigned. Tested in Task 1 (`sameModel` cases).
- After the equality skip, the "on this workspace" dot and workspace hints must still follow workspace switches (they read `focusedWorkspaceId`, not the model). Verified by reading the bindings in Task 1 Step 5; the user checks it by eye after the merge.
- Theme changes arriving in a burst must still end with icons from the new theme. Checked in Task 3 (single deferred run uses current state) and live in Task 6 (touch theme file → icons unchanged, one rebuild).
- A second urgent event after the calm-down must bounce again. Checked live in Task 6 (two notify-sends 12 s apart).
- Icon index: first occurrence still wins (SVG before PNG). Tested in Task 2.

---

## File Structure

```
DockModel.js            # + sameModel(a, b), + parseIconIndex(text)
Dock.qml                # refreshDock equality skip; icon index via StdioCollector + awk dedupe;
                        # theme change coalescing timer; closewindow single rebuild
components/DockItem.qml # urgent animation calms down after URGENT_ANIMATION_MS
components/DockCard.qml # shadow layers only while visible
tests/unit/dockmodel-perf.test.mjs   # node tests for sameModel / parseIconIndex
```

---

### Task 1: Skip identical model rebuilds

**Files:**
- Create: `tests/unit/dockmodel-perf.test.mjs`
- Modify: `DockModel.js` (new `sameModel`), `Dock.qml` (`refreshDock`)

**Interfaces:**
- Produces: `DockModel.sameModel(a, b) -> bool` — deep equality of two `buildEntries` results (plain objects, arrays, strings, numbers, booleans).

- [ ] **Step 1: Create the worktree**

```bash
cd ~/.config/omarchy/plugins/omadock && git fetch upstream
git worktree list | grep -q omadock-wt/perf || git worktree add -b feat/perf-fixes ~/.local/share/omadock-wt/perf upstream/main
cd ~/.local/share/omadock-wt/perf && git log --oneline -1
```

- [ ] **Step 2: Write the failing tests** — `tests/unit/dockmodel-perf.test.mjs`

```js
// Performance helpers in DockModel.js. DOCKMODEL overrides the file.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)

const win = (title, ws) => ({ title, address: "0x1", appId: "foot", workspaceName: ws, isMinimized: false })
const model = (title, ws) => ({
  pinned: [{ id: "foot", appId: "foot", pinned: true, running: true, windows: 1, windowList: [win(title, ws)] }],
  running: [],
  grouped: [],
})

test("sameModel: equal content in fresh objects", () => {
  assert.equal(M.sameModel(model("a", "2"), model("a", "2")), true)
})

test("sameModel: a window title change is a change", () => {
  assert.equal(M.sameModel(model("a", "2"), model("b", "2")), false)
})

test("sameModel: a workspace move is a change", () => {
  assert.equal(M.sameModel(model("a", "2"), model("a", "3")), false)
})

test("sameModel: an extra running app is a change", () => {
  const b = model("a", "2")
  b.running = [{ id: "zen", appId: "zen", pinned: false, running: true, windows: 1, windowList: [] }]
  assert.equal(M.sameModel(model("a", "2"), b), false)
})

test("sameModel: missing or empty models", () => {
  assert.equal(M.sameModel(null, model("a", "2")), false)
  assert.equal(M.sameModel({ pinned: [], running: [] }, { pinned: [], running: [] }), true)
})
```

- [ ] **Step 3: Run to verify it fails**

Run: `node --test tests/unit/dockmodel-perf.test.mjs`
Expected: all 5 FAIL with `M.sameModel is not a function`.

- [ ] **Step 4: Implement**

`DockModel.js`, after `buildEntries`:

```js
// The model holds only plain values (see buildEntries), so equal JSON means
// equal content. refreshDock skips assigning an equal model: every delegate
// binding re-evaluates on assignment, and most events (a workspace switch,
// a focus change) rebuild exactly the same model.
function sameModel(a, b) {
  if (!a || !b) return false
  return JSON.stringify(a) === JSON.stringify(b)
}
```

`Dock.qml` `refreshDock()`: replace

```qml
    root.dockModel = root.appLibrary
      ? DockModel.buildEntries(root.pinnedIds, tops, root.appRows,
                               root.appLibrary, root.hyprToplevelFor, root.minimizedWorkspace, root.minimizedOrigins, root.appGroups)
      : { pinned: [], running: [] }
```

with

```qml
    var next = root.appLibrary
      ? DockModel.buildEntries(root.pinnedIds, tops, root.appRows,
                               root.appLibrary, root.hyprToplevelFor, root.minimizedWorkspace, root.minimizedOrigins, root.appGroups)
      : { pinned: [], running: [] }
    // An equal model would only re-run every delegate's bindings.
    if (!DockModel.sameModel(next, root.dockModel)) root.dockModel = next
```

- [ ] **Step 5: Run tests and check consumers**

Run: `node --test tests/unit/dockmodel-perf.test.mjs` → 5 pass.
Run: `grep -n "focusedWorkspaceId\|focusedWorkspaceName" components/DockItem.qml` → `onFocusedWorkspace` reads them directly, so workspace switches still update it without a new model. Run `grep -n "dockModel\b" Dock.qml components/*.qml` and confirm nothing relies on a `dockModelChanged` signal for side effects other than the derived section bindings (record what you find in the ledger).

- [ ] **Step 6: Commit**

```bash
git add DockModel.js Dock.qml tests/unit/dockmodel-perf.test.mjs
git commit -m "perf(model): skip rebuilds that change nothing

Every workspace switch, focus change and window event rebuilt the dock
model and assigned it, so every delegate re-ran its bindings even when
the content was identical (a workspace switch moves no windows). The
rebuild now compares with the current model and keeps it when equal."
```

---

### Task 2: Icon index parsed once

**Files:**
- Modify: `DockModel.js` (new `parseIconIndex`), `Dock.qml` (`iconIndexScanCommand`, `iconIndexScan`, remove `indexIconLine`/`pendingIconIndex` if unused)
- Test: `tests/unit/dockmodel-perf.test.mjs`

**Interfaces:**
- Produces: `DockModel.parseIconIndex(text) -> { name: path }` — one entry per icon name (file name without extension), first occurrence wins.

- [ ] **Step 1: Write the failing tests** (append)

```js
test("parseIconIndex: first occurrence of a name wins", () => {
  const idx = M.parseIconIndex("/a/apps/foot.svg\n/b/apps/foot.png\n/c/places/folder.svg\n")
  assert.equal(idx.foot, "/a/apps/foot.svg")
  assert.equal(idx.folder, "/c/places/folder.svg")
  assert.equal(Object.keys(idx).length, 2)
})

test("parseIconIndex: blank lines and odd names", () => {
  const idx = M.parseIconIndex("\n  \n/x/org.app.Name.svg\n/x/.hidden\n/x/noext\n")
  assert.equal(idx["org.app.Name"], "/x/org.app.Name.svg")
  assert.equal(idx[".hidden"], "/x/.hidden")
  assert.equal(idx.noext, "/x/noext")
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test tests/unit/dockmodel-perf.test.mjs` → the two new tests FAIL (`not a function`).

- [ ] **Step 3: Implement**

`DockModel.js`:

```js
// Icon name -> file from the icon scan's output, one path per line. The
// name is the file name without its extension; the first path for a name
// wins (the scan lists SVGs before PNGs).
function parseIconIndex(text) {
  var index = {}
  var lines = String(text == null ? "" : text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var value = lines[i].trim()
    if (!value) continue
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name && index[name] === undefined) index[name] = value
  }
  return index
}
```

(`.hidden` keeps its name because `dot > 0` is false, same as `indexIconLine` today.)

`Dock.qml`:
1. `iconIndexScanCommand()`: wrap the loop in braces and pipe it through an order-preserving dedupe so only the first path per name reaches QML. Replace the returned array with:

```js
      return [
        'dirs="$HOME/.icons $HOME/.local/share/icons";',
        'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
        '{ for ext in svg png; do',
        '  for base in $dirs; do',
        '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/places/*" -o -path "*/mimetypes/*" \\) -name "*.$ext" 2>/dev/null;',
        '  done;',
        '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
        'done; } | awk -F/ \'{ n = $NF; sub(/\\.[^.]*$/, "", n); if (!(n in seen)) { seen[n] = 1; print } }\''
      ].join(' ')
```

and update its comment: `// SVGs before PNGs so the first hit per name is the scalable one; awk keeps only that first hit, so QML parses ~2 300 lines instead of ~23 600.`

2. `iconIndexScan`: replace the `SplitParser`, `onStarted` and `onExited` with:

```qml
    // One collected read, parsed once: a callback per line cost ~23 600
    // GUI-thread calls on every start and theme change.
    stdout: StdioCollector { id: iconIndexOut; waitForEnd: true }
    onExited: {
      localAppLibrary.iconIndex = DockModel.parseIconIndex(iconIndexOut.text)
      localAppLibrary.appsChanged()
    }
```

3. Run `grep -n "indexIconLine\|pendingIconIndex" Dock.qml components/*.qml`; remove `indexIconLine` and the `pendingIconIndex` property when nothing else uses them.

4. Check the awk program survives JS + bash quoting: extract the command and run it (from the worktree):

```bash
python3 - > <scratchpad>/iconcmd.sh <<'EOF'
import re
s = open('Dock.qml').read()
i = s.index('function iconIndexScanCommand()'); j = s.index("].join(' ')", i)
parts = re.findall(r"'((?:[^'\\]|\\.)*)'", s[i:j])
print(' '.join(p.encode().decode('unicode_escape') for p in parts))
EOF
bash <scratchpad>/iconcmd.sh | wc -l; bash <scratchpad>/iconcmd.sh | awk -F/ '{print $NF}' | sed 's/\.[^.]*$//' | sort | uniq -d | wc -l
```
Expected: about 2 300 lines and `0` duplicate names. If the extraction disagrees with what QML builds (JS string escapes), verify instead live in Task 6 Step 4.

- [ ] **Step 4: Run tests** — `node --test tests/unit/dockmodel-perf.test.mjs` → 7 pass.

- [ ] **Step 5: Commit**

```bash
git add DockModel.js Dock.qml tests/unit/dockmodel-perf.test.mjs
git commit -m "perf(icons): dedupe the icon scan before it reaches QML

The icon index scan streamed ~23 600 paths into a SplitParser, one JS
callback per line on the GUI thread, at start and on every theme change,
to keep ~2 300 names. awk now keeps the first path per name and the
output is parsed once."
```

---

### Task 3: One rebuild per theme change, one per closed window

**Files:**
- Modify: `Dock.qml` (`handleThemeChanged` → timer, closewindow branch)

- [ ] **Step 1: Coalesce theme changes**

Rename the body of `handleThemeChanged()` to a new `function applyThemeChange()` (unchanged content), and make `handleThemeChanged()`:

```qml
  // Up to five sources report one theme switch (three Color signals, the
  // icon theme file, the colors file); each used to rescan apps and rebuild
  // the dock. They now coalesce into one run once the burst is over.
  function handleThemeChanged() {
    themeChangeTimer.restart()
  }
```

Add next to the other timers:

```qml
  Timer {
    id: themeChangeTimer
    interval: 100
    onTriggered: root.applyThemeChange()
  }
```

Run `grep -n "handleThemeChanged()" Dock.qml` and check every caller is a change notification (signals / `onLoaded`), not a place that needs the result synchronously (e.g. `Component.onCompleted` reading `currentIconThemeName` right after). If one does, call `root.applyThemeChange()` there instead and ledger it.

- [ ] **Step 2: Single rebuild on closewindow**

In `onRawEvent`, the `closewindow` branch ends with `root.refreshDock()`; the shared block below already restarts `modelTimer` (40 ms) for `closewindow`. Delete the `root.refreshDock()` line in the closewindow branch.

- [ ] **Step 3: Commit**

```bash
git add Dock.qml
git commit -m "perf(events): coalesce theme changes and rebuild once per close

A theme switch reached the dock through up to five signals and each one
rescanned apps and rebuilt the model; they now coalesce into one run
100 ms after the burst. A closed window rebuilt the model twice, once
synchronously and once through the 40 ms model timer; only the timer
remains."
```

---

### Task 4: Urgent animation calms down

**Files:**
- Modify: `components/DockItem.qml` (pulse / bounce block, lines ~118-146)

- [ ] **Step 1: Implement**

Replace

```qml
  readonly property bool pulsing: item.urgent || item.starting
```

with

```qml
  // Urgency animates for URGENT_ANIMATION_MS, then only the indicator's
  // urgent colour remains: an unattended urgent window must not keep the
  // dock (and the compositor) redrawing forever. A new urgent event starts
  // it again.
  readonly property int urgentAnimationMs: 10000
  property bool urgentFresh: false
  onUrgentChanged: {
    item.urgentFresh = item.urgent
    if (item.urgent) urgentCalm.restart()
    else urgentCalm.stop()
  }
  Component.onCompleted: if (item.urgent) { item.urgentFresh = true; urgentCalm.restart() }
  Timer {
    id: urgentCalm
    interval: item.urgentAnimationMs
    onTriggered: item.urgentFresh = false
  }

  readonly property bool pulsing: item.starting || (item.urgent && item.urgentFresh)
```

and in `bouncing` replace `(item.urgent && root.showUrgentHint)` with `(item.urgent && item.urgentFresh && root.showUrgentHint)`. Leave both `SequentialAnimation`s as they are: their `running` bindings follow `pulsing`/`bouncing`, and the existing `onPulsingChanged` / `onBouncingChanged` handlers reset `pulse` and `bounceY` when they stop.

Run: `grep -n "Component.onCompleted" components/DockItem.qml` — if `DockItem` already has one, merge the urgent line into it instead of adding a second handler.

- [ ] **Step 2: Commit**

```bash
git add components/DockItem.qml
git commit -m "perf(urgent): stop the urgent animation after ten seconds

Urgent bounce and pulse looped forever while the dock was visible, so one
unattended urgent window kept the dock and Hyprland redrawing at the
monitor's refresh rate. The animation now stops after ten seconds; the
indicator keeps its urgent colour, and a new urgent event animates again."
```

---

### Task 5: Shadow layers only while visible

**Files:**
- Modify: `components/DockCard.qml` (~line 454)

- [ ] **Step 1: Implement**

Run `sed -n 440,470p components/DockCard.qml`; on the shadow segment with `layer.enabled: true`, change it to `layer.enabled: visible` with the comment `// No offscreen texture while the shadow is off (HoverFx does the same).` Check HoverFx.qml for the existing pattern (`grep -n "layer.enabled" components/HoverFx.qml`) and match it.

- [ ] **Step 2: Commit**

```bash
git add components/DockCard.qml
git commit -m "perf(card): keep shadow layers off while the shadow is hidden

The card's shadow segments always had layer.enabled, so their offscreen
textures existed with the shadow switched off."
```

---

### Task 6: Merge, measure, PR

- [ ] **Step 1: Offline tests in the worktree** — `node --test tests/unit/*.test.mjs` → all pass.

- [ ] **Step 2: Urgent "before" on the current live dock**

The live dock still runs the old code. Pick a running, unfocused app with a window (e.g. Thunderbird) and tell the user it will be marked urgent until they focus it. Then:
```bash
notify-send -a Thunderbird "omadock test" "urgent state for a benchmark"; sleep 12
python3 tests/bench/bench.py run --repeat 1 --out <scratchpad>/before   # S6 now runs
```
Record S6 `cpu_pct` and `hypr_cpu_pct` (expect clearly above S0).

- [ ] **Step 3: Merge into priard**

```bash
cd ~/.config/omarchy/plugins/omadock
git merge-tree --write-tree priard feat/perf-fixes >/dev/null && echo CLEAN
```
If CLEAN: `git merge --no-ff feat/perf-fixes -m "Merge branch 'feat/perf-fixes' into priard"`. Otherwise: `git worktree add -b merge/perf ~/.local/share/omadock-wt/merge-perf priard`, merge there, resolve keeping both sides' intent, run `node --test tests/unit/*.test.mjs`, commit, `git merge --ff-only merge/perf` in the live checkout, remove the temp worktree and branch. Then:
```bash
omarchy restart shell; sleep 8; bash tests/run-all.sh --all
```
Expected: ALL PASSED.

- [ ] **Step 4: Measure after**

```bash
notify-send -a Thunderbird "omadock test" "urgent state for a benchmark"; sleep 12
python3 tests/bench/bench.py run --events --repeat 3
python3 tests/bench/bench.py compare bench/results/2026-10-02-2339-omarchy-desk-pri.json bench/results/<new>.json
```
Expected: S6 cpu close to S0 after the 10 s calm-down; S5 cpu lower than baseline (4.42 %); no regression beyond noise elsewhere. Also send a second notify-send 12 s after the first and confirm with `omarchy-shell omadock itemGeometry` that the item is still `"urgent": true` (the state persists; the animation restarting is checked by the user by eye).
Icon index check: `journalctl --user --since "-60 s" | grep -iE "omadock/|TypeError"` empty and the dock icons look unchanged in a screenshot (`grim -o DP-1`, crop the dock region per CLAUDE.md) compared with one taken before the merge.
Theme burst: `touch ~/.config/omarchy/current/theme/icons.theme` 3 times 50 ms apart (find the watched path with `grep -n "icons.theme" Dock.qml`), check log clean and icons unchanged.

- [ ] **Step 5: Commit results, push, PR**

```bash
git add bench/results/*.json && git commit -m "test(bench): measurements after the perf fixes

Before/after for the urgent animation, workspace switching and idle."
git push fork priard
git -C ~/.local/share/omadock-wt/perf push -u fork feat/perf-fixes
```
Write the PR body (numbers from compare: S5, S6, S0; what each commit does; how to test) to `<scratchpad>/perf-pr.md` and ask the user before `gh pr create -R thepathless/omadock --head priard:feat/perf-fixes --base main --title "perf: skip no-op rebuilds, parse the icon index once, calm urgent animation" --body-file <scratchpad>/perf-pr.md`.
