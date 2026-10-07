# Panel Layout and Both-Sides Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A full-width bottom **Panel** layout next to the floating **Dock**, and a **Both sides** alignment that puts folders and drives at the right edge.

**Architecture:** Pure layout math in a new `DockLayout.js` (unit-tested in node). `Dock.qml` derives one `placement` object (`{ panel, split, align }`) from the stored `layout`, `alignment` and `splitSections`; everything that draws reads `placement`, not the raw settings. The card stretches to the window in Panel (and in Dock + split + Both sides), the icon `Row` is offset inside it, and folders/drives move into a nested `rightRow` so a flexible `spreadGap` can push them to the right edge without a binding loop.

**Tech Stack:** Quickshell 0.3.1 / Qt 6 QML, plain JS helpers, node `--test` + `node:vm`, bash live tests over `omarchy-shell omadock` IPC.

**Spec:** `docs/superpowers/specs/2026-10-07-panel-layout-design.md` (on `priard` only).

## Global Constraints

- Code, comments, commit messages in English; one topic per commit, body explains why; **no AI attribution** anywhere.
- Branch `feat/panel-layout` is cut from `feat/side-labels` (PR #47, which already contains PR #48 `feat/preset-defaults`). Never commit `FORK.md`, `manifest.json` version bumps, `docs/superpowers/` or `CLAUDE.md` on it.
- `layout`: `"dock"` (default) | `"panel"`; anything else reads as `"dock"`.
- `alignment`: `"left" | "center" | "right" | "spread"`; unknown values read as `"center"`. UI label for `spread` is "Both sides".
- Spread in Dock without Split sections behaves as `center`; spread with no folders and no drives behaves as `left`. Stored value is never rewritten by that fallback.
- Panel ignores Split sections, has square corners, rim on the top edge only, no `gapsOut` margin.
- Presets do not store `layout` or `alignment`.
- File-size rules (`python3 tests/static/structure-check.py`, upstream CI): `.qml/.js` ≤ 800 lines; `Dock.qml` ≤ its ceiling in `tests/static/structure-check.py` (2438 at plan time, Dock.qml is exactly at it); `components/logic/*.qml` stay pure `QtObject` with functions whose first parameter is `root`.
- The checkout is the live plugin: every write reloads the dock for ~0.5 s. New IPC functions need `omarchy restart shell` (wait ~5 s). Never synthesise keyboard input; never click.
- Shell snippets below use `SP=/tmp/claude-1000/-home-priard--config-omarchy-plugins-omadock/55f1ddcc-3b33-486f-a578-af82536ed67c/scratchpad` and `CFG=~/.config/omarchy/omadock.json`; set both in every new shell.
- Screenshots: `grim -o DP-1 f.png`, dock at physical y ≈ 2010–2160, x centred on 3840; crop with `magick`. Config variants: back up `~/.config/omarchy/omadock.json`, edit with Python, `sleep 1.5`, capture, restore.

## Review Focus

1. **Magnification across the spread gap** — hovering the last running app and the first folder must grow icons smoothly without the right group jumping or leaving the screen. Pinned by Task 5 Step 7 (home centres equal live centres at rest, ±1 px) and the user's hover test.
2. **Dragging folders in Both sides** — reordering folders and pinning a folder dropped from a file manager must land at the pointed index after folders moved into `rightRow`. Pinned by Task 5 Step 4 (drag logic offsets) and the user's drag test.
3. **Switching layouts at runtime** — Dock → Panel → Dock must restore the floating card exactly (x, width, bottom margin, radius, exclusive zone). Pinned by Task 4 Step 6 (itemGeometry before/after equal).
4. **Overflow** — more icons than fit the screen in Panel must not produce negative offsets or a negative gap. Pinned by Task 1 tests (`rowOffset` / `spreadGap` clamp to 0).
5. **Autohide in Panel** — the reveal strip spans the full width and intelligent autohide measures the panel without `gapsOut`. Pinned by Task 4 Step 5 (exclusive zone / reveal strip checks) and the user's autohide test.

---

### Task 0: Branch and working copy

**Files:** none.

- [ ] **Step 1: Keep the plan readable after the branch switch**

`docs/superpowers/` exists only on `priard`; switching branches removes it from the working tree.

```bash
SP=/tmp/claude-1000/-home-priard--config-omarchy-plugins-omadock/55f1ddcc-3b33-486f-a578-af82536ed67c/scratchpad
cp docs/superpowers/plans/2026-10-07-panel-layout.md docs/superpowers/specs/2026-10-07-panel-layout-design.md "$SP/"
```

- [ ] **Step 2: Create the branch from the current side-labels head**

```bash
cd ~/.config/omarchy/plugins/omadock
git status --short            # must be empty
git fetch upstream fork
git switch -c feat/panel-layout feat/side-labels
git merge-base --is-ancestor feat/preset-defaults HEAD && echo "has #48"
```
Expected: `has #48`. The live dock now runs this branch.

- [ ] **Step 3: Baseline**

Run: `bash tests/run-all.sh` (if absent on this branch — it is fork-only — run `node --test tests/unit/*.test.js tests/unit/*.test.mjs && python3 tests/static/structure-check.py`).
Expected: all pass. Also `bash tests/smoke-test.sh` → pass.

---

### Task 1: `DockLayout.js` — pure layout math

**Files:**
- Create: `DockLayout.js`
- Create: `tests/unit/layout.test.mjs`
- Modify: `.github/workflows/ci.yml:28`

**Interfaces:**
- Produces (all plain functions, no Qt):
  - `normalizeLayout(v) -> "dock" | "panel"`
  - `normalizeAlignment(v) -> "left" | "center" | "right" | "spread"`
  - `placement(layout, alignment, splitSections, hasRightGroup) -> { panel: bool, split: bool, align: "left"|"center"|"right"|"spread" }`
  - `spreadAvailable(layout, splitSections) -> bool`
  - `stretchedBox(place, windowWidth, inset) -> { x, width } | null`
  - `rowOffset(align, innerWidth, rowWidth) -> number ≥ 0`
  - `spreadGap(innerWidth, leftWidth, rightWidth, spacing) -> number ≥ 0`
  - `spreadHomeShift(innerWidth, restWidth) -> number ≥ 0`

- [ ] **Step 1: Write the failing tests**

`tests/unit/layout.test.mjs`:

```js
// Tests for DockLayout.js, the pure helpers behind the Dock / Panel layouts
// and the alignments. Plain JS with no Qt globals, run in a vm context.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKLAYOUT || new URL("../../DockLayout.js", import.meta.url)
const L = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), L)
const plain = (v) => JSON.parse(JSON.stringify(v))

test("normalizeLayout keeps panel, everything else is dock", () => {
  assert.equal(L.normalizeLayout("panel"), "panel")
  assert.equal(L.normalizeLayout("PANEL"), "panel")
  assert.equal(L.normalizeLayout("dock"), "dock")
  for (const v of ["", null, undefined, "taskbar", 3, {}]) assert.equal(L.normalizeLayout(v), "dock")
})

test("normalizeAlignment accepts the four values, else center", () => {
  for (const v of ["left", "right", "spread", "center"]) assert.equal(L.normalizeAlignment(v), v)
  assert.equal(L.normalizeAlignment("Right"), "right")
  for (const v of ["", null, undefined, "both", "top", 7]) assert.equal(L.normalizeAlignment(v), "center")
})

test("placement: panel ignores split", () => {
  assert.deepEqual(plain(L.placement("panel", "left", true, true)), { panel: true, split: false, align: "left" })
  assert.deepEqual(plain(L.placement("dock", "left", true, true)), { panel: false, split: true, align: "left" })
})

test("placement: spread needs panel or split, and a right group", () => {
  assert.equal(L.placement("dock", "spread", false, true).align, "center")
  assert.equal(L.placement("dock", "spread", true, true).align, "spread")
  assert.equal(L.placement("panel", "spread", false, true).align, "spread")
  assert.equal(L.placement("panel", "spread", false, false).align, "left")
  assert.equal(L.placement("dock", "spread", true, false).align, "left")
  assert.equal(L.placement("bogus", "bogus", "yes", true).align, "center")
  assert.equal(L.placement("bogus", "bogus", "yes", true).split, false)
})

test("spreadAvailable", () => {
  assert.equal(L.spreadAvailable("panel", false), true)
  assert.equal(L.spreadAvailable("dock", true), true)
  assert.equal(L.spreadAvailable("dock", false), false)
})

test("stretchedBox: panel spans the window, dock spread keeps the inset", () => {
  assert.deepEqual(plain(L.stretchedBox({ panel: true, split: false, align: "center" }, 5120, 20)), { x: 0, width: 5120 })
  assert.deepEqual(plain(L.stretchedBox({ panel: false, split: true, align: "spread" }, 5120, 20)), { x: 20, width: 5080 })
  assert.equal(L.stretchedBox({ panel: false, split: false, align: "center" }, 5120, 20), null)
  assert.equal(L.stretchedBox({ panel: false, split: true, align: "left" }, 5120, 20), null)
  assert.deepEqual(plain(L.stretchedBox({ panel: false, split: true, align: "spread" }, 10, 20)), { x: 20, width: 0 })
})

test("rowOffset per alignment, clamped at 0 on overflow", () => {
  assert.equal(L.rowOffset("left", 1000, 400), 0)
  assert.equal(L.rowOffset("right", 1000, 400), 600)
  assert.equal(L.rowOffset("center", 1000, 401), 300)
  assert.equal(L.rowOffset("spread", 1000, 400), 0)
  assert.equal(L.rowOffset("right", 300, 400), 0)
  assert.equal(L.rowOffset("center", 300, 400), 0)
})

test("spreadGap fills what is left between the groups, never negative", () => {
  assert.equal(L.spreadGap(1000, 300, 200, 4), 492)
  assert.equal(L.spreadGap(400, 300, 200, 4), 0)
})

test("spreadHomeShift moves resting right-group centres by the free width", () => {
  assert.equal(L.spreadHomeShift(1000, 600), 400)
  assert.equal(L.spreadHomeShift(500, 600), 0)
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test tests/unit/layout.test.mjs`
Expected: FAIL (`ENOENT ... DockLayout.js`).

- [ ] **Step 3: Implement `DockLayout.js`**

```js
// Pure helpers for the dock's layout (Dock or Panel) and its alignment
// (Dock.qml placement, components/DockCard.qml). Plain JS with no Qt
// globals, so the node tests run it in a vm context like DockLabels.js.

// "panel" spans the screen's bottom edge; anything else is the floating dock.
function normalizeLayout(v) {
  return String(v === undefined || v === null ? "" : v).toLowerCase() === "panel" ? "panel" : "dock"
}

// "spread" (Both sides) puts folders and drives at the right edge.
function normalizeAlignment(v) {
  var a = String(v === undefined || v === null ? "" : v).toLowerCase()
  return (a === "left" || a === "right" || a === "spread") ? a : "center"
}

// Both sides needs room to open a gap: the full-width panel, or a dock
// split into panels.
function spreadAvailable(layout, splitSections) {
  return normalizeLayout(layout) === "panel" || splitSections === true
}

// What the dock draws for the stored settings. The panel is one bar, so
// it ignores split sections; Both sides falls back to center where it
// cannot open a gap, and to left when nothing would go right.
function placement(layout, alignment, splitSections, hasRightGroup) {
  var panel = normalizeLayout(layout) === "panel"
  var split = !panel && splitSections === true
  var align = normalizeAlignment(alignment)
  if (align === "spread" && !spreadAvailable(layout, splitSections)) align = "center"
  if (align === "spread" && !hasRightGroup) align = "left"
  return { panel: panel, split: split, align: align }
}

// The card's x and width when it does not hug its icons: the panel spans
// the window; a spread dock spans it less the inset on each side. null:
// the card is as wide as its row.
function stretchedBox(place, windowWidth, inset) {
  if (place.panel) return { x: 0, width: windowWidth }
  if (place.align === "spread") return { x: inset, width: Math.max(0, windowWidth - 2 * inset) }
  return null
}

// Where the row starts inside a stretched card, past the content inset.
// A row wider than the card starts at the left edge.
function rowOffset(align, innerWidth, rowWidth) {
  var free = Math.max(0, innerWidth - rowWidth)
  if (align === "right") return free
  if (align === "center") return Math.round(free / 2)
  return 0
}

// Width of the gap between the left group and the right one; the gap item
// has the row spacing on both sides.
function spreadGap(innerWidth, leftWidth, rightWidth, spacing) {
  return Math.max(0, innerWidth - leftWidth - rightWidth - 2 * spacing)
}

// How far the right group's resting centres sit past where a packed row
// would put them: the card's free width at rest.
function spreadHomeShift(innerWidth, restWidth) {
  return Math.max(0, innerWidth - restWidth)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `node --test tests/unit/layout.test.mjs` → PASS. Then `node --check DockLayout.js`.

- [ ] **Step 5: CI syntax check**

`.github/workflows/ci.yml:28`:
```yaml
        run: node --check DockModel.js && node --check DockLabels.js && node --check DockLayout.js
```

- [ ] **Step 6: Commit**

```bash
git add DockLayout.js tests/unit/layout.test.mjs .github/workflows/ci.yml
git commit -m "feat(layout): pure helpers for the panel layout and both-sides alignment" -m "The panel and the Both sides alignment need the card's box, the row offset and the gap between the groups. Keeping that math in a plain JS file lets the node tests cover every layout and alignment combination without Qt."
```

---

### Task 2: Make room in `Dock.qml` (ratchet)

`Dock.qml` is at its ceiling; Tasks 3–5 add about ten lines to it. Move the minimized-tile model out first.

**Files:**
- Modify: `Dock.qml:321-352` (tileModel)
- Modify: `components/logic/DockStyleLogic.qml` (append function)
- Modify: `tests/static/structure-check.py:27` (ceiling)

**Interfaces:**
- Produces: `DockStyleLogic.tileModel(root) -> array` (body verbatim from Dock.qml).

- [ ] **Step 1: Move the body**

In `components/logic/DockStyleLogic.qml`, before the closing `}` of the QtObject, add:

```qml
  // Minimized-window preview tiles (macOS-style section on the dock's right).
  // In minimizeMode "all", a parked app's windows compress into ONE stacked
  // group tile; in "active" mode every window keeps its own tile.
  function tileModel(root) {
    if (!root.showMinimizedTiles) return []
    var list = root.minimizedWindows
    if (root.minimizeMode !== "all") {
      var singles = []
      for (var s = 0; s < list.length; s++) singles.push({ type: "single", win: list[s] })
      return singles
    }
    var groups = {}
    var order = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      var key = w.appId || w.address
      if (!groups[key]) {
        groups[key] = { type: "group", appId: key, title: w.title, windows: [] }
        order.push(key)
      }
      groups[key].windows.push(w)
    }
    // Oldest member parks the group's slot in line.
    order.sort(function (a, b) {
      var ta = root.parkedAt[groups[a].windows[0].address] !== undefined ? root.parkedAt[groups[a].windows[0].address] : 0
      var tb = root.parkedAt[groups[b].windows[0].address] !== undefined ? root.parkedAt[groups[b].windows[0].address] : 0
      return ta - tb
    })
    var out = []
    for (var g = 0; g < order.length; g++) out.push(groups[order[g]])
    return out
  }
```

In `Dock.qml` replace the three comment lines and the whole `readonly property var tileModel: { ... }` block with:

```qml
  // Minimized-window preview tiles (DockStyleLogic.tileModel).
  readonly property var tileModel: styleLogic.tileModel(root)
```

(QML records the properties the function reads as the binding's dependencies, so updates behave as before.)

- [ ] **Step 2: Lower the ceiling to the new length**

Run: `wc -l Dock.qml` (expect ~2408). Set `"Dock.qml": <that number>,` in `tests/static/structure-check.py`.
**Do not lower it again after Tasks 3–5** — the freed lines are their budget; at the end of Task 6 set the ceiling to the final length (Task 7 Step 2).

- [ ] **Step 3: Verify**

Run: `python3 tests/static/structure-check.py && bash tests/smoke-test.sh`
Expected: PASS, PASS. Live: `omarchy-shell omadock itemGeometry | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"` returns the same count as before the change (minimize a window first if you want tiles in it — or skip; the smoke test covers load errors).

- [ ] **Step 4: Commit**

```bash
git add Dock.qml components/logic/DockStyleLogic.qml tests/static/structure-check.py
git commit -m "refactor: move the minimized-tile model into DockStyleLogic" -m "Dock.qml sits at its line ceiling and the panel layout needs a few properties there. The tile model is pure computation over root state, so it moves to the style logic module verbatim and the ceiling drops with it."
```

---

### Task 3: Settings model — `layout`, `placement`, config, IPC

**Files:**
- Modify: `Dock.qml` (import, properties, setter; around lines 10–13, 637, 1200)
- Modify: `components/logic/DockConfigLogic.qml:104-105` (parse), `:171` (save)
- Modify: `components/logic/DockStateLogic.qml:76-82` (setters)
- Modify: `DockHost.qml:186-195` (IPC), `:212-224` (state)
- Modify: `tests/live/ipc-roundtrip.sh:36-37`

**Interfaces:**
- Consumes: `DockLayout.normalizeLayout`, `normalizeAlignment`, `placement` (Task 1).
- Produces on the Dock root:
  - `property string layout` (`"dock" | "panel"`)
  - `readonly property var placement` (`{ panel, split, align }`)
  - `readonly property real edgeGap` (`0` in Panel, else `Style.gapsOut`)
  - `function setDockLayout(l)`
  - IPC `setLayout(layout: string)`; `state()` gains `layout` and `align`.

- [ ] **Step 1: Dock.qml properties**

Add next to the other JS imports (line ~11):
```qml
import "DockLayout.js" as DockLayout
```
Replace `property string alignment: "center" // "center" | "left" | "right"` with:
```qml
  property string alignment: "center" // "center" | "left" | "right" | "spread"
  property string layout: "dock"      // "dock" | "panel" (DockLayout.js)
  // What the dock draws: { panel, split, align } (DockLayout.placement).
  readonly property var placement: DockLayout.placement(root.layout, root.alignment, root.splitSections, root.folderSlots + root.driveSlots > 0)
  // Margin between the card and the screen edge; the panel sits on it.
  readonly property real edgeGap: root.placement.panel ? 0 : Style.gapsOut
```
After `function setDockPosition(pos) ...` (line ~1201) add:
```qml
  function setDockLayout(l) { return stateLogic.setDockLayout(root, l) }
```

- [ ] **Step 2: Config parse and save**

`DockConfigLogic.qml` — add `import "../../DockLayout.js" as DockLayout` to its imports, then replace lines 104–105 with:
```qml
    root.alignment = DockLayout.normalizeAlignment(parsed ? (parsed.alignment || parsed.position) : "")
    root.layout = DockLayout.normalizeLayout(parsed ? parsed.layout : "")
```
In `buildConfig` after `conf.alignment = root.alignment || "center"` add:
```qml
    conf.layout = root.layout
```

- [ ] **Step 3: State setters**

`DockStateLogic.qml` — add the same import; replace the body of `setDockAlignment` and add `setDockLayout` after it:
```qml
  function setDockAlignment(root, align) {
    root.alignment = DockLayout.normalizeAlignment(align)
    root.saveConfig()
    if (root.intelligentAutohide) root.debounceOverlapTimerRef.restart()
    root.syncVisibility()
  }

  function setDockLayout(root, layout) {
    root.layout = DockLayout.normalizeLayout(layout)
    root.saveConfig()
    if (root.intelligentAutohide) root.debounceOverlapTimerRef.restart()
    root.syncVisibility()
  }
```

- [ ] **Step 4: IPC**

`DockHost.qml`, after `setPosition`:
```qml
    // Layout is a config key; the other docks pick it up from the file.
    function setLayout(layout: string): void {
      var d = host.orderedDocks()
      if (d.length > 0) d[0].setDockLayout(layout)
    }
```
In `state()` add two fields:
```qml
        layout: d[0].layout,
        align: d[0].placement.align,
```

- [ ] **Step 5: Live round-trip test (fails until restart)**

`tests/live/ipc-roundtrip.sh`, after the `ipc setAlignment "$align"; sleep 0.5` line:
```bash
layout=$(python3 -c "import json; print(json.load(open('$CFG')).get('layout', 'dock'))")
ipc setLayout panel; sleep 0.5
[ "$(st layout)" = panel ] || fail "setLayout panel"
ipc setAlignment spread; sleep 0.5
[ "$(st align)" = spread ] || [ "$(st align)" = left ] || fail "setAlignment spread in panel"
ipc setLayout bogus; sleep 0.5
[ "$(st layout)" = dock ] || fail "setLayout bogus -> dock"
ipc setLayout "$layout"; ipc setAlignment "$align"; sleep 0.5
```

- [ ] **Step 6: Restart and run**

```bash
omarchy restart shell; sleep 6
bash tests/smoke-test.sh && bash tests/live/ipc-roundtrip.sh
python3 tests/static/structure-check.py
```
Expected: PASS ×3. Nothing looks different yet (Panel geometry is Task 4).

- [ ] **Step 7: Commit**

```bash
git add Dock.qml components/logic/DockConfigLogic.qml components/logic/DockStateLogic.qml DockHost.qml tests/live/ipc-roundtrip.sh
git commit -m "feat(layout): layout and spread alignment settings with IPC" -m "Adds the layout key (dock or panel) and the spread alignment, and one placement object that resolves them against split sections and the folder and drive sections, so the drawing code reads a single source. setLayout joins setAlignment over IPC and state() reports both for the live tests."
```

---

### Task 4: Panel geometry

**Files:**
- Modify: `Dock.qml` (`pointerX` ~278, `separatorWidth` ~310, `effectiveCardRadius` ~408, `labelPlates` ~912, line ~461, overlap check ~1049–1056, `dockWindow` ~2242–2290)
- Modify: `components/DockCard.qml` (wrapper x/margins, hitbox, shadow, card width/border, row x, divider visibility, unpin bubble)
- Modify: `components/DockSurface.qml:29-31`

**Interfaces:**
- Consumes: `root.placement`, `root.edgeGap` (Task 3); `DockLayout.stretchedBox`, `rowOffset` (Task 1).
- Produces on `DockCard` (`cardWrapper`): `readonly property var stretch` (`{x,width}|null`), `readonly property real innerWidth`, `readonly property real rowOffset`.

- [ ] **Step 1: Split and radius read `placement`**

`Dock.qml`:
- `separatorWidth`: `root.splitSections ? ...` → `root.placement.split ? ...`
- `labelPlates`: `&& !root.splitSections` → `&& !root.placement.split`
- `effectiveCardRadius`: first line of the block body becomes
  ```qml
    if (root.placement.panel) return 0
  ```
  (labels' `dockRatio` and every surface follow it).

`components/DockCard.qml`: in `segments`, `if (!root || !root.splitSections) return full` → `if (!root || !root.placement.split) return full`; the four divider `Rectangle`s: `visible: !(root && root.splitSections)` → `visible: !(root && root.placement.split)`.

- [ ] **Step 2: Card box, margin and row offset (DockCard.qml)**

Add `import "../DockLayout.js" as DockLayout` to the imports. Below `folderDropActive` add:
```qml
  // The card's box when it spans the window (panel, or a spread dock); null
  // while it hugs its icons. innerWidth is the room for the row inside it.
  readonly property var stretch: (root && parent) ? DockLayout.stretchedBox(root.placement, parent.width, Style.gapsOut * 2) : null
  readonly property real innerWidth: dockCard.width - dockCard.contentLeftInset - dockCard.contentRightInset
  readonly property real rowOffset: (root && stretch) ? DockLayout.rowOffset(root.placement.align, innerWidth, row.implicitWidth) : 0
```
Wrapper:
```qml
  readonly property real shadowRoom: (root && !root.placement.panel && root.showShadow && root.showBackground && root.shadowStrength > 0) ? Style.space(5) : 0
  anchors.bottomMargin: (root && root.dockVisible) ? root.edgeGap + cardWrapper.shadowRoom : -(dockCard.height + (root ? root.edgeGap : 0) + cardWrapper.shadowRoom + 10)

  x: {
    if (!parent) return 0
    if (cardWrapper.stretch) return cardWrapper.stretch.x
    var ax = DockLabels.anchoredX(parent.width, width, Style.gapsOut * 2, root ? root.placement.align : "center", 0)
    ...unchanged
  }
```
Hitbox:
```qml
    x: (root && root.placement.panel) ? 0 : -Style.space(24)
    width: dockCard.width + ((root && root.placement.panel) ? 0 : Style.space(48))
    height: dockCard.height + ((root && root.dockVisible) ? (root.edgeGap + Style.space(18)) : 0)
```
Shadow: `padBottom: Math.max(0, (root ? root.edgeGap : 0) + cardWrapper.shadowRoom - cardShadow.drop)`.
Card:
```qml
    borderSpec: (root && !root.showBorder)
      ? Border.none()
      : Border.flat("transparent", (root && root.placement.panel) ? dockCard.effectiveBorderWidth + " 0 0 0" : dockCard.effectiveBorderWidth)
    ...
    width: cardWrapper.stretch ? cardWrapper.stretch.width : row.implicitWidth + contentLeftInset + contentRightInset
```
Row: `x: dockCard.contentLeftInset + cardWrapper.rowOffset`.
Unpin bubble `windowTop`: `Style.gapsOut` → `(root ? root.edgeGap : Style.gapsOut)`.

- [ ] **Step 3: Rim on the top edge only (DockSurface.qml)**

```qml
  borderSpec: (root && !root.showBorder)
    ? Border.none()
    : Border.flat(surface.effectiveBorderColor, (root && root.placement.panel) ? surface.borderWidth + " 0 0 0" : surface.borderWidth)
```
(`Border.flat` takes a CSS-like width string: `"top right bottom left"`.)

- [ ] **Step 4: Pointer in row coordinates (Dock.qml)**

```qml
  readonly property real pointerX: cardHover.hovered
    ? cardHover.point.position.x - dockCardComp.rowOffset
    : -1e6
```
(Home centres are measured from the row's start, as they are from the card's in the floating dock; subtracting the offset keeps the wave identical.)

- [ ] **Step 5: Window (Dock.qml)**

- line ~461: `- Style.gapsOut -` → `- root.edgeGap -`
- overlap check ~1049–1056: `Style.gapsOut * 2` → `root.edgeGap * 2` (both lines) and `- Style.gapsOut` → `- root.edgeGap`
- `exclusiveZone`: `+ Style.gapsOut * 2` → `+ root.edgeGap * 2`
- `implicitHeight`: `+ Style.gapsOut +` → `+ root.edgeGap +`
- reveal strip:
  ```qml
      x: {
        if (dockCardComp && dockCardComp.stretch) return 0
        var cardW = ...unchanged
        if (root.placement.align === "left") return Style.gapsOut
        if (root.placement.align === "right") return parent.width - targetW - Style.gapsOut
        return Math.round((parent.width - targetW) / 2)
      }
      width: {
        if (dockCardComp && dockCardComp.stretch) return parent.width
        ...unchanged
      }
  ```
- Then: `python3 tests/static/structure-check.py` → PASS (Dock.qml under the Task 2 ceiling).

- [ ] **Step 6: Live check**

```bash
CFG=~/.config/omarchy/omadock.json; cp $CFG $SP/cfg.bak
ipc() { omarchy-shell omadock "$@"; }
ipc itemGeometry > $SP/geo-dock.json
for a in left center right; do ipc setLayout panel; ipc setAlignment $a; sleep 1.5; grim -o DP-1 $SP/panel-$a.png; done
ipc setLayout dock; ipc setAlignment "$(python3 -c "import json;print(json.load(open('$SP/cfg.bak')).get('alignment','center'))")"; sleep 1.5
ipc itemGeometry > $SP/geo-dock-after.json
cmp $SP/geo-dock.json $SP/geo-dock-after.json && echo "dock restored"
hyprctl -j layers | python3 -c "import json,sys; d=json.load(sys.stdin); [print(l['namespace'], l['x'], l['y'], l['w'], l['h']) for m in d.values() for lv in m['levels'].values() for l in lv if l['namespace']=='omadock']"
cp $SP/cfg.bak $CFG
```
Expected: `dock restored`; crops (`magick panel-X.png -crop 7680x220+0+1940 X-crop.png`) show a square full-width bar flush with the bottom, rim only on top, icons left / centred / right. While in Panel, `hyprctl monitors -j` `reserved` bottom equals the card height (autohide off) — check once with `ipc setLayout panel` and restore. `bash tests/smoke-test.sh` → PASS and `journalctl --user --since "-2 min" | grep -iE "omadock/|binding loop"` → empty.

- [ ] **Step 7: Commit**

```bash
git add Dock.qml components/DockCard.qml components/DockSurface.qml
git commit -m "feat(layout): panel spans the bottom edge" -m "In the panel layout the card takes the window's width, sits on the screen edge with square corners and a rim on its top edge only, and reserves exactly its height. Alignment moves the icon row inside it; the pointer is measured from the row so the magnification wave behaves as on the floating dock. Split sections do not apply to the one-piece bar."
```

---

### Task 5: Both sides (spread)

**Files:**
- Modify: `components/DockCard.qml` (nested `rightRow`, `spreadGap`, home shift, segments)
- Modify: `components/logic/DockDragLogic.qml:16-35, 207-212`
- Modify: `components/logic/DockLabelLogic.qml:33` (mirror)

**Interfaces:**
- Consumes: `cardWrapper.stretch`, `innerWidth` (Task 4); `DockLayout.spreadGap`, `spreadHomeShift` (Task 1); `root.labelExtras`, `DockLabels.extrasTotal`.
- Produces on `DockCard`: `readonly property var rightRowRef` (the nested Row holding folderSeparator → drives), `readonly property real spreadShift`.

- [ ] **Step 1: Nest the right group**

In `DockCard.qml`'s `row`, wrap everything from `Item { id: folderSeparator` through the drives `Repeater` (inclusive) in:
```qml
      // Folders and drives: the right group of the Both sides alignment.
      // Its own Row so the gap before it can be sized from its width
      // without the outer row measuring itself.
      Row {
        id: rightRow
        spacing: row.spacing
        anchors.verticalCenter: parent.verticalCenter
        visible: root ? (root.hasFolderSeparator || root.folderSlots > 0 || root.driveSlots > 0 || trailingDropGap.open) : true
        ...the moved items, re-indented by two spaces...
      }
```
and directly before it:
```qml
      // Both sides: the free width between the groups.
      Item {
        id: spreadGap
        visible: root ? root.placement.align === "spread" : false
        width: visible ? DockLayout.spreadGap(cardWrapper.innerWidth, spreadGap.x, rightRow.implicitWidth, row.spacing) : 0
        height: 1
      }
```
Add at the top of `cardWrapper`: `readonly property var rightRowRef: rightRow`.

- [ ] **Step 2: Separators inside the nested row in `segments`**

Replace the `segments` body after the `full` early return with:
```qml
    var dpr = dockCard.dpr
    var origin = cardWrapper.x + dockCard.x
    var inset = dockCard.contentLeftInset
    var gap = Math.max(1, Math.round(root.sectionGap * dpr)) / dpr
    var snap = function(v) { return Math.round((v + origin) * dpr) / dpr - origin }
    var spread = root.placement.align === "spread"
    // Each cut: where the panel before it ends (row x of the cut item) and,
    // for the spread gap, where the next one starts.
    var cuts = []
    if (leftTileSeparator.visible) cuts.push({ at: leftTileSeparator.x })
    if (separator.visible) cuts.push({ at: separator.x })
    if (spread) cuts.push({ at: spreadGap.x, next: rightRow.x + (folderSeparator.visible ? folderSeparator.x + folderSeparator.width + row.spacing : 0) })
    else if (folderSeparator.visible) cuts.push({ at: rightRow.x + folderSeparator.x })
    if (driveSeparator.visible) cuts.push({ at: rightRow.x + driveSeparator.x })
    var out = []
    var start = 0
    for (var i = 0; i < cuts.length; i++) {
      var end = snap(row.x + cuts[i].at - row.spacing + inset)
      out.push({ x: start, width: Math.max(0, end - start) })
      start = cuts[i].next !== undefined ? snap(row.x + cuts[i].next - inset) : end + gap
    }
    out.push({ x: start, width: Math.max(0, dockCard.width - start) })
    return out
```

- [ ] **Step 3: Home centres of the right group**

Below `rowOffset` in `cardWrapper`:
```qml
  // Both sides: how far the right group rests past a packed row, from the
  // resting widths, so the magnification wave never measures itself.
  readonly property real spreadShift: (root && root.placement.align === "spread")
    ? DockLayout.spreadHomeShift(innerWidth, root.baseRowWidth + DockLabels.extrasTotal(root.labelExtras)) : 0
```
In the folder delegate's and the drive delegate's `slotHomeCenter(...)` call, change the last argument `root.tilesFixedWidth` → `root.tilesFixedWidth + cardWrapper.spreadShift`.

- [ ] **Step 4: Drag logic — folder positions are now rightRow-local**

`DockDragLogic.qml`:
```qml
  function inPinZone(root, card, px) {
    var rx = px - card.rightRowRef.x
    if (card.folderSeparatorRef.visible) return rx >= card.folderSeparatorRef.x - (root ? root.gapWidth : 0)
    if (card.foldersRepeater.count > 0) {
      var first = card.foldersRepeater.itemAt(0)
      if (first) return rx >= first.x
    }
    return px >= card.row.width - (root ? root.iconSlot * 0.75 : 0)
  }

  function folderInsertIndex(root, card, px) {
    var rx = px - card.rightRowRef.x
    var n = card.foldersRepeater ? card.foldersRepeater.count : 0
    for (var i = 0; i < n; i++) {
      var it = card.foldersRepeater.itemAt(i)
      if (!it) continue
      // The middle of the folder's tile (icon and any label), past the drop gap.
      var gap = it.gapWidth || 0
      var iconCenter = it.x + gap + (it.width - gap) / 2
      if (rx < iconCenter) return i
    }
    return n
  }
```
In `handleFolderDragMoved`, after `var rx = mx - card.row.x` add `var fx = rx - card.rightRowRef.x` and use `fx` in the range test (`fx < first.x - ...`, `fx > last.x + ...`); keep passing `rx` to `folderInsertIndex` (it subtracts the offset itself).

- [ ] **Step 5: Divider line and label mirror**

- Folder separator's `Rectangle`: `visible: !(root && (root.placement.split || root.placement.align === "spread"))` (the gap is the separation).
- `DockLabelLogic.qml:33`: `mirror: !!root && (root.placement.align === "right" || (root.placement.align === "spread" && kind === "folders")),`

- [ ] **Step 6: Static checks**

Run: `python3 tests/static/structure-check.py && bash tests/static/qmllint.sh && node --test tests/unit/*.test.js tests/unit/*.test.mjs`
Expected: PASS (DockCard.qml ≤ 800 lines; qmllint no new warning kinds — if one is reviewed and accepted, `tests/static/qmllint.sh --update`).

- [ ] **Step 7: Live check — positions and resting home centres**

Add a temporary IPC to `DockHost.qml` (remove in Step 8):
```qml
    function debugHomes(): string {
      var d = host.orderedDocks()[0]; var c = d.dockCardComp; var out = []
      for (var i = 0; i < c.foldersRepeater.count; i++) { var it = c.foldersRepeater.itemAt(i); out.push({ home: Math.round(it.homeCenter), live: Math.round(it.mapToItem(d.dockCard, it.width / 2, 0).x - c.rowOffset) }) }
      return JSON.stringify({ shift: c.spreadShift, gap: c.rightRowRef.x, folders: out })
    }
```
(If `homeCenter` is measured to the icon rather than the whole tile when labels are on, compare with labels off.) Then:
```bash
omarchy restart shell; sleep 6
cp $CFG $SP/cfg.bak
hyprctl dispatch 'hl.dsp.cursor.move({x=2560, y=1250})'   # pointer away from the dock
for combo in "panel spread" "dock spread"; do set -- $combo
  python3 - "$CFG" "$1" <<'EOF'
import json,sys; p=sys.argv[1]; c=json.load(open(p)); c["layout"]=sys.argv[2]; c["alignment"]="spread"; c["splitSections"]= sys.argv[2]=="dock"; json.dump(c,open(p,"w"),indent=2)
EOF
  sleep 1.5; omarchy-shell omadock debugHomes; grim -o DP-1 $SP/spread-$1.png
done
cp $SP/cfg.bak $CFG
```
Expected: for every folder `|home - live| ≤ 1`; the last drive/folder ends at the right inset (`itemGeometry`: right edge ≈ screen width − inset); screenshots show the left group at the left edge and folders/drives at the right edge, one bar in Panel and two floating panels in Dock + split. No "binding loop" in `journalctl --user --since "-2 min"`.
Hover check without clicks: `hyprctl dispatch 'hl.dsp.cursor.move({x=X, y=1250})'` then move to the first folder's centre (logical, from `itemGeometry`) and grab a screenshot; icons grow, nothing leaves the screen. Restore the pointer.

- [ ] **Step 8: Remove the debug IPC, verify, commit**

```bash
# delete the debugHomes function from DockHost.qml by hand, then:
git diff --stat DockHost.qml   # must be empty
grep -n debugHomes DockHost.qml || echo "gone"
omarchy restart shell; sleep 6; bash tests/smoke-test.sh
git add components/DockCard.qml components/logic/DockDragLogic.qml components/logic/DockLabelLogic.qml
git commit -m "feat(layout): both sides alignment" -m "Folders and drives move into their own row so a gap before them can take the card's free width: the apps stay at the left edge and the folders and drives at the right, in the panel and in a split dock. Their resting centres shift by the same free width, so magnification and folder drags keep working across the gap."
```

---

### Task 6: Settings UI and search

**Files:**
- Modify: `components/settings/SettingsPlacement.qml:15-27`
- Modify: `components/settings/SettingsAppearance.qml` (rows `dividerLength`, `dividerStyle`, `dividerWidth`, `dividerOpacity`, `dividerHeight`, `corners`, `cornerRadius`, `splitSections`, `panelSpacing`)
- Modify: `SettingsSearch.js:103`

**Interfaces:**
- Consumes: `root.layout`, `root.alignment`, `root.placement`, `root.setDockLayout`, `root.setDockAlignment`, `DockLayout.spreadAvailable`.

- [ ] **Step 1: Placement page**

Add `import "../../DockLayout.js" as DockLayout`. Replace the Position section rows with:
```qml
  SectionLabel { text: "Position" }

  ChoiceRow {
    key: "layout"
    label: "Layout"
    hint: "Panel spans the screen's full width along the bottom edge."
    options: [
      { value: "dock", label: "Dock" },
      { value: "panel", label: "Panel" }
    ]
    value: root ? root.layout : "dock"
    onPicked: function(v) { root.setDockLayout(v) }
  }
  ChoiceRow {
    key: "alignment"
    label: "Alignment"
    readonly property bool spreadOk: root ? DockLayout.spreadAvailable(root.layout, root.splitSections) : false
    hint: !spreadOk
      ? (root && root.alignment === "spread"
        ? "Both sides needs Split sections (Appearance); centred until then."
        : "Both sides needs Split sections (Appearance).")
      : (root && root.alignment === "spread" ? "Folders and drives go to the right edge." : "")
    options: {
      var list = [
        { value: "left", label: "Left" },
        { value: "center", label: "Center" },
        { value: "right", label: "Right" }
      ]
      if (spreadOk) list.push({ value: "spread", label: "Both sides" })
      return list
    }
    value: root ? (root.alignment || "center") : "center"
    onPicked: function(v) { root.setDockAlignment(v) }
  }
```
(The Omarchy `ButtonGroup` has no disabled state, so the unavailable option is left out and the hint says why.)

- [ ] **Step 2: Appearance page**

- The five divider rows: every `!root.splitSections` → `!root.placement.split`.
- `corners` ChoiceRow: add `visible: root ? !root.placement.panel : true`.
- `cornerRadius`: `visible: root ? (!root.placement.panel && root.dockShape === "rounded") : false`.
- `splitSections`: add `visible: root ? !root.placement.panel : true`.
- `panelSpacing`: `visible: root ? root.placement.split : false`.

- [ ] **Step 3: Search**

`SettingsSearch.js`, before the `alignment` entry:
```js
  { key: "layout", page: "placement", label: "Layout", terms: ["panel", "taskbar", "dock", "full width", "bar", "edge"] },
```
and extend the `alignment` terms: `["left", "center", "right", "position", "both sides", "spread", "split"]`.

- [ ] **Step 4: Verify**

```bash
node --test tests/unit/*.test.js tests/unit/*.test.mjs && python3 tests/static/structure-check.py && bash tests/static/qmllint.sh
omarchy-shell omadock openSettingsPage placement; sleep 1; grim -o DP-1 $SP/settings-placement.png
cp $CFG $SP/cfg.bak; omarchy-shell omadock setLayout panel; sleep 1; grim -o DP-1 $SP/settings-placement-panel.png
omarchy-shell omadock openSettingsPage appearance; sleep 1; grim -o DP-1 $SP/settings-appearance-panel.png
omarchy-shell omadock closeSettings; cp $SP/cfg.bak $CFG
```
Expected: Layout row present; Both sides offered only in Panel or with split; in Panel the Appearance page has no Corners, Corner radius, Split sections or Panel spacing rows. Log clean.

- [ ] **Step 5: Commit**

```bash
git add components/settings/SettingsPlacement.qml components/settings/SettingsAppearance.qml SettingsSearch.js
git commit -m "feat(settings): layout and both sides on the placement page" -m "The placement page gains a Dock / Panel choice and offers Both sides where it can apply, saying when it needs split sections. In the panel the shape and split rows go away, since a full-width bar has square corners and is one piece."
```

---

### Task 7: Docs, ratchet, full verification

**Files:**
- Modify: `README.md:211-215, 307, 478, 573`
- Modify: `tests/static/structure-check.py:27`

- [ ] **Step 1: README**

- §8 list: `- **\`"center"\`, \`"left"\`, \`"right"\`, \`"spread"\`** (Both sides: apps left, folders and drives right) along the bottom edge, ...` and a new bullet `- **Panel layout** (\`"layout": "panel"\`): a full-width bar on the bottom edge; alignment moves the icons inside it.`
- line 307: `- **Placement & Alignment**: Dock or Panel layout; \`Left\`, \`Center (Default)\`, \`Right\`, \`Both sides\`.`
- config table: alignment row values add `"spread"`; new row after it:
  `| \`layout\` | \`string\` | \`"dock"\` | \`"dock"\` floats above the edge; \`"panel"\` spans the full width on the bottom edge. |`
- IPC list: `setAlignment("center" | "left" | "right" | "spread")` and `- \`setLayout("dock" | "panel")\`: Switch between the floating dock and the full-width panel.`

- [ ] **Step 2: Ratchet**

Set `"Dock.qml"` in `tests/static/structure-check.py` to `wc -l < Dock.qml`.

- [ ] **Step 3: Full run**

```bash
node --test tests/unit/*.test.js tests/unit/*.test.mjs
python3 -m unittest discover -s tests/unit -p 'test_*.py'
python3 tests/static/structure-check.py && python3 tests/static/security-grep.py && bash tests/static/shaders-in-sync.sh && bash tests/manifest-check.sh .
bash tests/static/qmllint.sh
omarchy restart shell; sleep 6; bash tests/smoke-test.sh && bash tests/live/ipc-roundtrip.sh && bash tests/live/config-fuzz.sh
```
Expected: all PASS. `tests/live/config-fuzz.sh` also with `{"layout": 5, "alignment": ["x"]}` — add that case to its list if the script has a list of payloads.

- [ ] **Step 4: Screenshot set for the user and the PR**

Panel × left / center / right / both sides; Dock + split + both sides; Panel with label plates (`labelMode: "always"`, `labelBackground: "plate"`); crop each to the bottom 220 px. Restore the config.

- [ ] **Step 5: Commit**

```bash
git add README.md tests/static/structure-check.py
git commit -m "docs(readme): panel layout and both sides alignment" -m "Documents the layout key, the spread alignment and the setLayout IPC call, and lowers the Dock.qml ceiling to its new length."
```

- [ ] **Step 6: Hand over for manual tests (stop here)**

Ask the user to test: clicking, dragging apps and folders (incl. across the gap and a folder dropped from a file manager), magnification across the gap, autohide and intelligent autohide in Panel, multi-monitor if used. Then, after their OK: switch back to `priard`, dry-run `git merge-tree --write-tree priard feat/panel-layout`, merge, `git push fork priard feat/panel-layout`. **No PR to thepathless/omadock until the user says go** (and it states "depends on #47 / #48").
