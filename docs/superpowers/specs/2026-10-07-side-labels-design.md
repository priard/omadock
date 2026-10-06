# Side labels — design

Date: 2026-10-07. Target: one upstream PR (`feat/side-labels`, base
`experimental`) that replaces the below/above name labels added in
upstream d380a4b.

## Why

The current labels sit in a band under (or over) the icon row. In practice:

- each label is `tile.width + space(10)` wide, wider than the slot pitch, so
  the pills overlap and read as one continuous strip;
- the fixed width truncates almost every name mid-word ("Mattermo…",
  "Zen Brow…");
- apps without a desktop entry show the raw class id ("org.omar…");
- the band crowds the window indicator dots and grows the dock;
- for apps the label repeats what the tooltip already says.

The replacement puts the name to the right of the icon, either always or
revealed on hover, drops the tooltip where the label already says
everything, and gives the label its own look options.

## Scope

Labels apply to apps, app groups and folders (the author's `labelKind`
filter stays). Minimized-window tiles and drives are untouched. The dock is
horizontal only.

## 1. Layout

**Tile width** = `iconSlot × magnify + labelExtra`, where
`labelExtra = progress × min(measuredTextWidth + padding, labelMaxWidth)`.
`progress` is 1 in `always` mode; in `hover` mode it animates 0→1
(~180 ms, the hover-effect easing). The icon stays at the tile's leading
edge; the window indicator dots stay under the icon.

**Anchor (hover mode).** The dock is centred and its width is the row's
implicit width, so a tile growing to the right would shift the hovered icon
left by half the label width and out from under the pointer, collapsing the
label again (oscillation). While the pointer is inside the dock, its
leading edge is pinned and the dock grows away from it: the hovered icon
and everything before it stay put. When the pointer leaves, labels collapse
and the dock eases back to its aligned position.

**Mirror.** With `alignment: right` the label opens to the left of the icon
and the right edge is the anchor, so the dock never grows past the screen.

**Dwell.** A label opens after ~150 ms on an icon so a sweep across the dock
does not ripple. Moving from an open label to another icon switches
immediately (one collapses while the next expands), like the tooltip linger
from #26.

**Arithmetic.**
- The dock root keeps a per-slot list of label extras; `slotHomeCenter`
  (the zoom/wave reference) adds the prefix sum of the extras before the
  slot, and `baseRowWidth` adds their total.
- `DockDragLogic` computes the icon centre as
  `it.x + it.width - iconSlot / 2` (icon at the trailing edge); it switches
  to the icon's own position so the drop gap lands correctly on wide tiles.
- The prefix-sum and mirror maths live in pure functions in a new
  `DockLabels.js`.

## 2. Rendering

**Name.** Desktop-entry `Name` as today. Apps without an entry get a
prettified id instead of the raw class: last dotted segment, `-`/`_` to
spaces, capitalised (`org.omarchy.terminal` → "Terminal",
`zen-browser` → "Zen Browser"). Groups and folders keep their user names.
A per-app override (`labelNames`) always wins.

**Shortening** (computed when the name, font, size or max width changes,
never per frame), each step only if the previous one did not fit:
1. clean: drop parenthesised parts and anything after ` - `, ` — `, `: `
   ("Signal - Private Messenger" → "Signal");
2. whole words: keep as many whole words as fit, no ellipsis
   ("Visual Studio Code" → "Visual Studio");
3. ellipsis: only when the first word alone does not fit ("Spotifasola…").

Measurement uses `TextMetrics` with the label's actual font; the JS function
takes an injected `fits(text)` so node tests can drive it. Any shortened
name counts as truncated for the tooltip rule.

**Placement in the tree.** The label lives inside `HoverFx` together with
the icon, and `HoverFx` covers icon plus label, so lift raises both (one
floor shadow), glitch splits the whole button, glow's halo and ripple follow
icon and text. Zoom/wave scale only the icon; the text keeps its size and
stays vertically centred on the icon.

**Look options**

| Option | Values |
|---|---|
| Font | theme · mono (JetBrains Mono) · pixel (bundled Silkscreen, OFL) |
| Size | small · medium · large (pixel snaps to the font's grid) |
| Color | theme · high contrast · theme accent |
| Background | none · pill (behind the text) · plate (one rounded plate behind icon and name, hover colour) |
| Reveal | slide (width + fade) · typewriter · scramble |
| Effect | none · accent glow · shadow/outline |

Reveal runs when a label appears: on expand in hover mode, on dock start or
a newly added item in always mode. Typewriter and scramble swap `text` on a
timer (~25 ms per character, capped at ~300 ms total); scramble draws random
characters from the font's own alphabet. On collapse typewriter erases from
the end, slide and scramble fade. Effects are static: glow is a
`MultiEffect` blur tinted with the accent (stronger on hover), shadow uses
`Text.Outline`/`Text.Raised`.

## 3. Tooltip

For an item whose label is visible, the tooltip shows only when it adds
something beyond the name:
- the app has windows to preview (window card stack), or
- there is a state hint (`[starting…]`, `[minimized]`, other workspace), or
- the label name was shortened.

Otherwise (a pinned app that is not running, a folder, a group) there is no
tooltip. When the tooltip does show it is unchanged, name included. In hover
mode the tooltip keeps its own `tooltipDelay` and anchors to the icon, which
does not move (section 1). Labels off or the item outside `labelKind`:
behaviour as today. One `tooltipNeeded(...)` function in
`DockLabelLogic`, used by DockItem, DockAppGroupItem and DockFolderItem.

## 4. Settings, config, migration

| Key | Values | Default |
|---|---|---|
| `labelMode` | `off` · `always` · `hover` | `off` |
| `labelKind` | `all` · `apps` · `groups` · `folders` | `all` |
| `labelFont` | `theme` · `mono` · `pixel` | `theme` |
| `labelSize` | `small` · `medium` · `large` | `small` |
| `labelColor` | `theme` · `high` · `accent` | `theme` |
| `labelBackground` | `none` · `pill` · `plate` | `none` |
| `labelReveal` | `slide` · `typewriter` · `scramble` | `slide` |
| `labelEffect` | `none` · `glow` · `shadow` | `none` |
| `labelMaxWidth` | 80–240 (px) | 140 |
| `labelNames` | `{ appId: name }`, ≤ 200 entries, names ≤ 40 chars | `{}` |

**Migration** in `DockConfigLogic` on read; old keys are deleted on write
(as `magnification` → `hoverEffect`):
- `showLabels: true` → `labelMode: "always"`, `false` → `"off"`;
- `labelPlacement` → dropped;
- `labelContrast: "pill"` → `labelBackground: "pill"`, `labelColor: "theme"`;
  `"high"` → `labelColor: "high"`.

**Settings page** (Appearance, replacing the current "Name labels" block):
Mode (Off / Always / On hover); when not Off: Show on, Font, Size, Color,
Background, Reveal, Effect, Max width. `SettingsSearch.js` entries with
synonyms (names, titles, text, caption, pixel, typewriter, …).

**Presets.** `labelFont`, `labelSize`, `labelColor`, `labelBackground`,
`labelReveal`, `labelEffect`, `labelMaxWidth` join `LOOK_KEYS`.
`labelMode`, `labelKind` and `labelNames` stay out (behaviour and data).

**Context menu.** "Rename label…" on apps, shown when labels apply to apps;
inline edit like the group rename in `AppGroupPopup`; an empty name restores
the desktop-entry name.

**Pixel font.** `fonts/Silkscreen-Regular.ttf` + `fonts/OFL.txt`, loaded by a
`FontLoader` only while `labelFont` is `pixel`; licence noted in the README.

## 5. Testing, performance, PR

**Unit tests** (`tests/unit/labels.test.mjs` over `DockLabels.js`):
`shortenName` (each step, empty, very long, Unicode), `prettyAppId`,
label extras / home centres (prefix sums, separators, mirror),
`tooltipNeeded` case table, config migration and `labelNames` bounds.

**Static.** Upstream `structure-check.py` ratchets: new logic goes to
`DockLabelLogic.qml` and `DockLabels.js`; `Dock.qml` must not grow past its
ceiling. No new qmllint warnings in touched files; security grep clean.

**Live.** Screenshots via config swaps: always × fonts × backgrounds, hover
mid-animation (temporary debug IPC forcing hover on an index, removed before
commit), right alignment, lift/glitch/glow/zoom with labels. The user tests
pointer sweeps (anchor, no oscillation), drag and drop over wide tiles, and
rename.

**Performance.** Always mode is static. Hover mode relayouts the row for
~180 ms per reveal, comparable to zoom. Typewriter/scramble timers run only
while revealing. Glow adds one `MultiEffect` per visible label only when
selected. `tests/bench/bench.py` before and after (idle, hover sweep).

**PR.** `feat/side-labels` from `upstream/experimental`, topical commits:
layout (extras + anchor), rendering + fonts + effects, tooltip, settings +
migration + rename, tests, README + screenshot. The body explains why
below/above is replaced, with before/after screenshots on `pr-assets`.
