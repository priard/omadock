# Nested Plates and Side Mark Size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `nested` Corners value that squares plates off against each other and rounds the outer ones along their panel's edge, plates in split sections, and full-size marks in the plates' side column.

**Architecture:** Two pure helpers in `DockLabels.js` decide which plate stands at a panel edge (from section counts, not geometry) and what its four corner radii are; `DockCard` builds the section list in its own row order, plates (`DockLabel`, `TilePlate`) read per-corner radii. Plates in split is a one-line gate change plus live verification. The mark size is one rule in `DockMarkGeometry.js`.

**Tech Stack:** QML (Qt 6.11, Quickshell 0.3.1), plain JS modules run by `node --test` in a vm context, Python PIL for screenshot measurement.

**Spec:** `docs/superpowers/specs/2026-10-10-nested-plates-design.md`

## Global Constraints

- `labelShape` values: `dock | pill | rounded | square | nested`; `dock` stays the default; no config migration.
- Nested outer radius: `min(h / 2, max(0, R - gap))`, `R = min(effectiveCardRadius, dockCard.height / 2)`, `gap = plateSpacing.gap`. Inner corners 0.
- `Dock.qml` is at its line cap (2412 in `tests/static/structure-check.py`): it may not grow. Net zero lines there.
- Branches from `upstream/experimental`: `feat/nested-plates` (worktree `~/.local/share/omadock-wt/nested`), `feat/side-mark-size` (worktree `~/.local/share/omadock-wt/marks`). Never commit FORK.md, manifest bumps, `docs/superpowers/` or CLAUDE.md on them.
- No AI attribution in commits. One topic per commit, body explains why. Code and comments in English.
- The live checkout (`~/.config/omarchy/plugins/omadock`, branch `priard`) is the running dock: merge a branch into it only after `git merge-tree --write-tree priard <branch>` shows no conflicts; after merging, `omarchy restart shell` and `bash tests/smoke-test.sh`.
- Never synthesise keyboard input; no clicks. Screenshots: `grim -o DP-1`, config variants by backing up `~/.config/omarchy/omadock.json`, editing with Python, `sleep 1.5`, capture, restore.

## Review Focus

- Split with an empty section in the middle (no running apps, folders present): the cut must land before the next non-empty section; test in Task 1 (`pending cut carries to the next section`).
- Drives as the last item (no plate there): the last folder plate must stay square on the right; test in Task 1.
- Omarchy button hidden (`showAppsButton: false`): slot 0 is then the first pinned app and it must take the left rounding; test in Task 1.
- Hover labels and the Pill background with `nested`: no edges, so they must look exactly like `dock`; test in Task 1 (`no edges → uniform`), checked live in Task 2.
- Pill-shaped dock (R = dockH / 2) with plate height Dock: nested outer radius must equal half the plate height (true pill ends), not the `0.32 h` cap; test in Task 1.

---

### Task 1: Pure helpers `plateEdges` and `plateCorners`

**Files:**
- Modify: `DockLabels.js:12` (LABEL_SHAPES), `DockLabels.js:235-243` (after `labelRadius`)
- Test: `tests/unit/labels.test.mjs`

**Interfaces:**
- Produces: `DockLabels.plateEdges(sections) -> Array<{left: bool, right: bool}>` indexed by label slot, where `sections` is `Array<{n: int, labelled: bool, cut: bool}>`.
- Produces: `DockLabels.plateCorners(shape, h, radius, outer, edges) -> {tl, tr, bl, br}`; `edges` is `{left, right}` or null/undefined.

- [ ] **Step 1: Create the worktree**

```bash
cd ~/.config/omarchy/plugins/omadock && git fetch upstream
git worktree add -b feat/nested-plates ~/.local/share/omadock-wt/nested upstream/experimental
cd ~/.local/share/omadock-wt/nested
```

- [ ] **Step 2: Write the failing tests** (append to `tests/unit/labels.test.mjs`)

```js
test("plateEdges: one panel without split, its outermost items are the edges", () => {
  // Omarchy button, three pinned, no tiles, two running, two folders, no drives.
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 3, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 2, labelled: true, cut: false }, { n: 0, labelled: false, cut: false }]))
  assert.equal(e.length, 8)
  assert.deepEqual(e[0], { left: true, right: false })
  for (let i = 1; i < 7; i++) assert.deepEqual(e[i], { left: false, right: false })
  assert.deepEqual(e[7], { left: false, right: true })
})

test("plateEdges: a drive at the edge leaves the last plate square", () => {
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 1, labelled: false, cut: false }]))
  assert.equal(e.length, 3)
  assert.deepEqual(e[2], { left: false, right: false })
})

test("plateEdges: split cuts each section into its own panel", () => {
  // button + 2 pinned | 2 running | 2 folders
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 2, labelled: true, cut: true },
    { n: 2, labelled: true, cut: true }, { n: 0, labelled: false, cut: false }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [
    [true, false], [false, false], [false, true],
    [true, false], [false, true],
    [true, false], [false, true]])
})

test("plateEdges: unlabelled tiles in their own split panel", () => {
  // 2 pinned | 2 tiles | 1 running: the pinned run ends a panel, the running one is alone.
  const e = plain(L.plateEdges([
    { n: 0, labelled: true, cut: false }, { n: 2, labelled: true, cut: false },
    { n: 2, labelled: false, cut: true }, { n: 1, labelled: true, cut: true }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [[true, false], [false, true], [true, true]])
})

test("plateEdges: a pending cut carries to the next section with items", () => {
  // Both sides + split, no folders, a drive: the cut before folders lands before the drive,
  // so the last running plate rounds on the right.
  const e = plain(L.plateEdges([
    { n: 1, labelled: true, cut: false }, { n: 1, labelled: true, cut: false },
    { n: 0, labelled: false, cut: false }, { n: 0, labelled: true, cut: true },
    { n: 0, labelled: true, cut: true }, { n: 1, labelled: false, cut: false }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [[true, false], [false, true]])
})

test("plateEdges: without the Omarchy button the first pinned app takes the left edge", () => {
  const e = plain(L.plateEdges([{ n: 0, labelled: true, cut: false }, { n: 2, labelled: true, cut: false }]))
  assert.deepEqual(e.map((x) => [x.left, x.right]), [[true, false], [false, true]])
})

test("plateEdges: empty row and a cut before the first item", () => {
  assert.deepEqual(plain(L.plateEdges([])), [])
  assert.deepEqual(plain(L.plateEdges([{ n: 1, labelled: true, cut: true }])), [{ left: true, right: true }])
})

test("plateCorners: any shape but nested rounds all four corners alike", () => {
  assert.deepEqual(plain(L.plateCorners("dock", 40, 6, 9, { left: true, right: false })), { tl: 6, tr: 6, bl: 6, br: 6 })
  assert.deepEqual(plain(L.plateCorners("pill", 40, 12.8, 9, null)), { tl: 12.8, tr: 12.8, bl: 12.8, br: 12.8 })
})

test("plateCorners: nested without edges (pill, hover) looks like dock", () => {
  assert.deepEqual(plain(L.plateCorners("nested", 40, 6, 9, null)), { tl: 6, tr: 6, bl: 6, br: 6 })
  assert.deepEqual(plain(L.plateCorners("nested", 40, 6, 9, undefined)), { tl: 6, tr: 6, bl: 6, br: 6 })
})

test("plateCorners: nested squares inner corners and rounds the edge side", () => {
  assert.deepEqual(plain(L.plateCorners("nested", 40, 6, 9, { left: false, right: false })), { tl: 0, tr: 0, bl: 0, br: 0 })
  assert.deepEqual(plain(L.plateCorners("nested", 40, 6, 9, { left: true, right: false })), { tl: 9, tr: 0, bl: 9, br: 0 })
  assert.deepEqual(plain(L.plateCorners("nested", 40, 6, 9, { left: false, right: true })), { tl: 0, tr: 9, bl: 0, br: 9 })
  assert.deepEqual(plain(L.plateCorners("nested", 40, 6, 9, { left: true, right: true })), { tl: 9, tr: 9, bl: 9, br: 9 })
})

test("plateCorners: nested outer radius stops at a pill end and never goes negative", () => {
  // Pill dock 72 high, gap 6: R - gap = 30 = half of a 60 px plate, not the 0.32 h cap.
  assert.deepEqual(plain(L.plateCorners("nested", 60, 19.2, 30, { left: true, right: false })), { tl: 30, tr: 0, bl: 30, br: 0 })
  assert.equal(L.plateCorners("nested", 40, 6, 50, { left: true, right: false }).tl, 20)
  assert.equal(L.plateCorners("nested", 40, 6, -3, { left: true, right: false }).tl, 0)
})

test("readLabelConfig accepts the nested corners", () => {
  assert.equal(L.readLabelConfig({ labelMode: "always", labelShape: "nested" }).labelShape, "nested")
})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `node --test tests/unit/labels.test.mjs`
Expected: FAIL, `L.plateEdges is not a function` / `L.plateCorners is not a function`, and the readLabelConfig test gets `"dock"`.

- [ ] **Step 4: Implement**

In `DockLabels.js:12`:

```js
var LABEL_SHAPES = ["dock", "pill", "rounded", "square", "nested"]
```

After `labelRadius` (keep its body; extend its comment with one line: `"nested" draws as "dock" wherever a background has no panel edge to follow (pills, hover labels).`), add:

```js
// Which plates stand at their panel's edge, by label slot. sections is the
// row in order (DockCard), each { n, labelled, cut }: n visible items,
// labelled when those items have label slots, cut when split sections start
// a new panel before them. A cut before an empty section carries to the
// next one with items. Counted, not measured, so the magnification wave
// cannot move an edge.
function plateEdges(sections) {
  var items = []
  var panel = 0
  var pending = false
  for (var i = 0; i < (sections || []).length; i++) {
    var s = sections[i]
    if (s.cut) pending = true
    for (var k = 0; k < (s.n || 0); k++) {
      if (pending && items.length > 0) panel++
      pending = false
      items.push({ panel: panel, labelled: !!s.labelled })
    }
  }
  var out = []
  for (var j = 0; j < items.length; j++) {
    if (!items[j].labelled) continue
    out.push({
      left: j === 0 || items[j - 1].panel !== items[j].panel,
      right: j === items.length - 1 || items[j + 1].panel !== items[j].panel
    })
  }
  return out
}

// A plate's corner radii { tl, tr, bl, br }. Every shape but "nested", and
// "nested" without edges, rounds all four by radius. "nested" squares the
// plate off inside its panel and, on a side at the panel's edge, uses outer
// (the panel's radius less the gap) so the two curves run parallel, up to
// a pill end.
function plateCorners(shape, h, radius, outer, edges) {
  if (shape !== "nested" || !edges) return { tl: radius, tr: radius, bl: radius, br: radius }
  var r = Math.max(0, Math.min(h / 2, Number(outer) || 0))
  var l = edges.left ? r : 0
  var rr = edges.right ? r : 0
  return { tl: l, tr: rr, bl: l, br: rr }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `node --test tests/unit/labels.test.mjs`
Expected: PASS (all tests, the old ones included).

- [ ] **Step 6: Commit**

```bash
git add DockLabels.js tests/unit/labels.test.mjs
git commit -m "feat(labels): helpers for nested plate corners

plateEdges tells which plate stands at its panel's edge from the row's
section counts, so the wave cannot move an edge; plateCorners turns that
into four radii, square inside a panel and parallel to the panel's own
curve on its edge. The Corners setting accepts the new value nested."
```

### Task 2: Draw nested corners (one panel)

**Files:**
- Modify: `components/DockCard.qml` (new property after `spreadShift`, ~line 44)
- Modify: `components/logic/DockLabelLogic.qml:45` (style gets `nestedRadius`)
- Modify: `components/DockLabel.qml:251` (plateRect radius)
- Modify: `components/TilePlate.qml:36`
- Modify: `components/settings/SettingsLabels.qml:124-137`, `SettingsSearch.js:99`, `README.md:331`, `README.md:548`

**Interfaces:**
- Consumes: `DockLabels.plateEdges`, `DockLabels.plateCorners` (Task 1).
- Produces: `DockCard.plateEdges` (reached as `root.dockCardComp.plateEdges`), `style.nestedRadius` in `labelStyle(kind)`.

- [ ] **Step 1: DockCard builds the section list** (after the `spreadShift` property)

```qml
  // Which label plates stand at their panel's edge, by label slot
  // (DockLabels.plateEdges): the row's sections in order, cut where split
  // sections cut the card into panels (as segments does).
  readonly property var plateEdges: (root && root.labelPlates) ? DockLabels.plateEdges([
    { n: root.appsSlots, labelled: true, cut: false },
    { n: root.pinnedSection.length + root.groupSlots, labelled: true, cut: false },
    { n: root.tileElements, labelled: false, cut: root.placement.split && root.hasLeftTileSeparator },
    { n: root.visibleRunningCount, labelled: true, cut: root.placement.split && root.hasSeparator },
    { n: root.folderSlots, labelled: true, cut: root.placement.split && (root.hasFolderSeparator || root.placement.align === "spread") },
    { n: root.driveSlots, labelled: false, cut: root.placement.split && root.hasDriveSeparator }
  ]) : []
```

- [ ] **Step 2: The style carries the nested radius** (`DockLabelLogic.qml`, next to `dockRatio`)

```js
      // Nested corners: the panel's drawn radius less the plate gap.
      nestedRadius: (root && dockH > 0 && root.labelPlates) ? Math.max(0, Math.min(root.effectiveCardRadius, dockH / 2) - root.plateSpacing.gap) : 0,
```

- [ ] **Step 3: DockLabel's plate takes four radii** (replace the `radius:` line of `plateRect`, line 251)

```qml
    readonly property real baseRadius: label.style ? Math.min(height * 0.32, DockLabels.labelRadius(label.style.shape, height, label.style.dockRatio)) : 0
    // Nested corners know the plate's place in its panel only in a plate row.
    readonly property var corners: DockLabels.plateCorners(label.style ? label.style.shape : "dock", height, baseRadius,
      label.style ? label.style.nestedRadius : 0,
      (spacing && label.root.dockCardComp) ? label.root.dockCardComp.plateEdges[label.slot] : null)
    radius: baseRadius
    topLeftRadius: corners.tl
    topRightRadius: corners.tr
    bottomLeftRadius: corners.bl
    bottomRightRadius: corners.br
```

- [ ] **Step 4: TilePlate the same, for slot 0** (replace line 36)

```qml
  readonly property real baseRadius: style ? Math.min(height * 0.32, DockLabels.labelRadius(style.shape, height, style.dockRatio)) : 0
  // The Omarchy button is label slot 0 (Dock.appsSlots).
  readonly property var corners: DockLabels.plateCorners(style ? style.shape : "dock", height, baseRadius,
    style ? style.nestedRadius : 0, (root && root.dockCardComp) ? root.dockCardComp.plateEdges[0] : null)
  radius: baseRadius
  topLeftRadius: corners.tl
  topRightRadius: corners.tr
  bottomLeftRadius: corners.bl
  bottomRightRadius: corners.br
```

- [ ] **Step 5: Settings, search, README**

`SettingsLabels.qml` Corners row: options become Dock, Nested, Pill, Rounded, Square (`{ value: "nested", label: "Nested" }` after Dock); hint:
`"Dock follows the dock's own corners. Nested squares plates off against each other and rounds the outer ones along the dock's edge."`

`SettingsSearch.js:99` terms gain `"nested"`.

`README.md:331`: `**Corners**: \`Dock\` (follows the dock's own corners), \`Nested\` (square between plates, the outer ones rounded along the dock's edge), \`Pill\`, \`Rounded\` or \`Square\`.`
`README.md:548`: `` `"dock"` (the dock's own corner ratio), `"nested"` (square between plates, the panel's radius less the gap on its edges; like `"dock"` for pills and hover labels), `"pill"`, `"rounded"` or `"square"`. ``

- [ ] **Step 6: Offline gates**

Run: `node --test tests/unit/*.test.mjs tests/unit/*.test.js && python3 tests/static/structure-check.py && /usr/lib/qt6/bin/qmllint components/DockCard.qml components/DockLabel.qml components/TilePlate.qml components/settings/SettingsLabels.qml components/logic/DockLabelLogic.qml 2>&1 | grep -iE "error|syntax"`
Expected: tests PASS, structure-check PASSED, no qmllint error/syntax lines.

- [ ] **Step 7: Commit, merge into priard, live check**

```bash
git add -A && git commit -m "feat(labels): nested corners square plates off and round the outer ones

With Corners set to Nested, plates meet each other and the dividers with
square corners, and the plates at the dock's edge round with the dock's
radius less the gap, so the curves run parallel. Pills and hover labels
have no edge to follow and keep the Dock look."
cd ~/.config/omarchy/plugins/omadock && git merge-tree --write-tree priard feat/nested-plates >/dev/null && git merge --no-edit feat/nested-plates
omarchy restart shell; sleep 5; bash tests/smoke-test.sh
```

Live: set `labelShape: "nested"`, `labelPlateHeight` `dock` then `icon`, `shape` `rounded` / `round` / `square`; `grim -o DP-1`, crop the dock (y ≈ 1990-2160 physical, x around 3840) and look at both outer ends and two inner joins. Expected: inner corners square, outer corners concentric with the dock's; square dock all square; `labelMode: "hover"` and `labelBackground: "pill"` with nested look as with dock. Restore the config.

### Task 3: Plates in split sections

**Files:**
- Modify: `Dock.qml:910` (net zero lines)
- Modify: `README.md:331` (one sentence), `tests/live/layout.sh` only if a failing assertion shows the plates need it

**Interfaces:**
- Consumes: `DockCard.plateEdges` cut flags (Task 2) — already split-aware.

- [ ] **Step 1: Lift the gate**

```qml
  readonly property bool labelPlates: root.labelMode === "always" && root.labelBackground === "plate"
```

- [ ] **Step 2: Commit, merge, restart, smoke**

```bash
git commit -am "feat(labels): plates in split sections

Each section is its own panel and keeps the plate rules: one gap from
plate to plate and to the section's edge, the same plate height and side
indicators. With Nested corners the outermost plates of every section
round with it."
cd ~/.config/omarchy/plugins/omadock && git merge-tree --write-tree priard feat/nested-plates >/dev/null && git merge --no-edit feat/nested-plates
omarchy restart shell; sleep 5; bash tests/smoke-test.sh
```

- [ ] **Step 3: Measure the section gaps**

Config variant: `splitSections: true`, `labelMode: always`, `labelBackground: plate`, `labelShape: nested`, `bgFill: solid`, `bgColor` a flat custom grey if the schema allows it (else the theme), `labelPlateHeight: dock`. Capture with grim and measure with PIL, scanning one row through the plates' vertical middle: list the x runs where the colour is the panel colour vs the plate colour vs the wallpaper.

```python
from PIL import Image
im = Image.open("split.png").convert("RGB")
y = 2075  # physical row through the plates
row = [im.getpixel((x, y)) for x in range(im.width)]
runs, start = [], 0
for x in range(1, len(row) + 1):
    if x == len(row) or sum(abs(a - b) for a, b in zip(row[x], row[start])) > 24:
        runs.append((start, x - start, row[start])); start = x
for r in runs:
    if r[1] >= 2: print(r)
```

Expected: every panel-colour run between a section edge and its outer plate is the same width as the runs between plates (± 1 physical px); every section gap equals `sectionSpacing` × 1.5 px. If a section edge is off by a pixel, fix it in `DockCard.segments` (snap the segment ends from the plate edges, which are already on the grid) and commit that as its own `fix(labels)` commit with the measured numbers in the body. Repeat with `labelPlateHeight: icon`, `alignment: spread` (split on), and `layout: panel` (split ignored: one panel, square corners).

- [ ] **Step 4: README** — in `README.md:331` replace the closing sentence with: `with plates on, the gap between plates, to the dock's edges and to a divider is one and the same; with split sections every section keeps that gap to its own edges.` Commit `docs(readme): plates in split sections`.

### Task 4: Full-size marks in the side column

**Files:**
- Modify: `DockMarkGeometry.js:17-20` (header comment), `DockMarkGeometry.js:38-39`
- Test: `tests/unit/markgeometry.test.mjs`

**Interfaces:**
- Produces: `DockMarkGeometry.dotSpace(dense, vertical)` returns `DOT` whenever `vertical`; `cell`, `dot`, `column` follow. `DockIndicator` already draws the upright bar as thick as `dotSize`.

- [ ] **Step 1: Worktree**

```bash
cd ~/.config/omarchy/plugins/omadock
git worktree add -b feat/side-mark-size ~/.local/share/omadock-wt/marks upstream/experimental
cd ~/.local/share/omadock-wt/marks
```

- [ ] **Step 2: Update the tests first** in `tests/unit/markgeometry.test.mjs`:
  - `cell: ...`: `assert.equal(G.cell(space(1), 1, false, true), 5)    // side column draws the full dot` and add `assert.equal(G.cell(space(1), 1, true, true), 5)`.
  - `dot: ...`: `assert.equal(G.dot(space(1), 1, false, true), 5)` and add `assert.equal(G.dot(space(1), 1.5, true, true), 8 / 1.5)   // 8 device px at 1.5x, dense or not`.
  - `a plate reserves ...`: `assert.deepEqual(plain(G.column(space(1), 1)), { edge: 1, width: 5, gap: 5 })`; reword its comment: the side column draws the full dot and its upright bar as thick, so the reserved room is one cell at every scale and density.
  - `a mark is never bigger ...`: `assert.equal(G.cell(dense, 2, true, true), 2)` with the comment `// at 2x the column's full dot is 2 px, the bar 1`.

Run: `node --test tests/unit/markgeometry.test.mjs` — Expected: FAIL on the changed assertions.

- [ ] **Step 3: Implement**

```js
// The dot's spacing: dense marks use the smaller one; a side column keeps
// the full dot, dense or not, so a couple of dots beside a plate do not
// look lost (the upright bar there is as thick as the dot).
function dotSpace(dense, vertical) { return (vertical || !dense) ? DOT : DOT_DENSE }
```

and in the header comment: `a 5 px dot (4 px when the marks are dense under the icon; a side column keeps 5)`.

- [ ] **Step 4: Gates**

Run: `node --test tests/unit/*.test.mjs tests/unit/*.test.js && python3 -m unittest discover -s tests/unit -p 'test_*.py' 2>&1 | tail -3`
Expected: PASS / OK.

- [ ] **Step 5: Commit, merge, live check**

```bash
git commit -am "feat(indicators): full-size marks in the plates' side column

Beside a plate the column drew the dense 4 px dot so it matched the
upright bar; two dots without the bar looked too small next to the art.
The column now draws the full dot and the bar as thick, and the plate
reserves the wider column."
cd ~/.config/omarchy/plugins/omadock && git merge-tree --write-tree priard feat/side-mark-size >/dev/null && git merge --no-edit feat/side-mark-size
omarchy restart shell; sleep 5; bash tests/smoke-test.sh
```

Live: screenshot a plate with two windows and no focus (dots only) and one with a focused window (bar). Expected: dots and bar 8 physical px across, centred on one line (measure with PIL on the crop); no plate content shifted into the name.

### Task 5: Wrap-up in the fork

- [ ] **Step 1:** `bash tests/run-all.sh` in the live checkout — Expected: ALL PASSED (update the qmllint baseline only if the change is reviewed and explained).
- [ ] **Step 2:** Bump `manifest.json` to `4.3.4-priard.2`, FORK.md "Not upstream yet": `feat/nested-plates` (Nested corners, plates in split) and `feat/side-mark-size`; commit `chore(fork): 4.3.4-priard.2 with nested plates and side mark size`.
- [ ] **Step 3:** `git push fork priard feat/nested-plates feat/side-mark-size` (retry on "remote rejected").
- [ ] **Step 4:** Hand over to the user for clicking and dragging on plates in split; no upstream PR until they say so.
