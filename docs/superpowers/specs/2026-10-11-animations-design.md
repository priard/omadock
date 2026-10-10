# Animations: entry/exit everywhere, one motion source, Full / Reduced / Off

Date: 2026-10-11. Status: approved in chat. One upstream PR (`feat/animations`).

## Problem

The dock has no layout transitions. Items enter partly animated only as a side
effect of always-on labels (the label grows 180 ms) and leave in one frame:
`KeyedListModel.sync` removes the key, the Repeater destroys the delegate, the
card width and x snap, and in split mode a whole section panel can vanish.
Tiles, folders, buttons and drives rebuild every delegate on any change.
Popups (menu, folder stack, group) are destroyed on close and their opacity
Behaviors never run. Window marks and the badge pop in and out. Durations and
easings drift (120 linear vs 120 OutCubic, 140, 150, 160, 180; autohide 300 vs
220). The launch bounce snaps back mid-air when a window appears.

## Setting

Motion & Effects → **Animations: Full / Reduced / Off** (`animations`, default
`full`). A behaviour preference: not part of presets, stored in omadock.json,
in the settings search.

| | Full | Reduced | Off |
|---|---|---|---|
| Row items in/out | slot width 0↔1, content scale 0.6↔1, opacity | short fade in place, layout snaps | instant |
| Card, split panels, dividers | follow the row smoothly | snap | snap |
| Popups (menu, folder, group) | fade + 6 px rise (like tooltips) | fade | instant |
| Window marks, badge | grow/shrink from scale + fade; badge width eases | fade | instant |
| Labels | as today (reveal, typewriter, scramble) | whole name, fade | instant |
| Launch bounce, pulse, urgent bounce, glitch, glow ripple | as today | off | off |
| Magnify, Lift/Glow hover | as today | as today | final state at once |
| Autohide | slide + fade | fade | instant |

Timing tokens: `fast` 120 ms (fades, colours), `base` 180 ms (layout, popups,
row items), `slow` 300 ms (autohide). Easing OutCubic entering, InCubic
leaving. Effects that are animations themselves (bounce, pulse, glitch,
ripple, reveal) keep their own timings but obey `oneShots` / `reveal`.

Launch bounce: when the app's window appears mid-bounce the current hop
finishes before it stops (no snap from 13 px to 0).

## Architecture

1. **`DockMotion.js`** (new, pure, unit-tested): `normalizeLevel(v)`;
   `plan(level)` → `{ level, fast, base, slow, layout, scale, rise, oneShots,
   reveal, fade }`. Full: every flag true. Reduced: `fade` and the
   durations stay, `layout`, `scale`, `rise`, `oneShots`, `reveal` false. Off:
   every duration 0 and every flag false. Easing constants documented in
   the file.
2. **`Dock.qml`**: `property string animations: "full"` and `readonly property
   var motion: DockMotion.plan(root.animations)`, with two lines moved out of
   Dock.qml so its ceiling holds. Config read/write in `DockConfigLogic`,
   validation via `normalizeLevel`. Settings row on the Motion & Effects page,
   `SettingsSearch.js` entry.
3. **Keys with a leaving state**: `DockKeys.js` (new, pure, unit-tested)
   `diff(rows, want, initial)` → operations (mark leaving, revive, move,
   insert with `fresh`), plus each row's `slot` (position counting live rows
   only). `KeyedListModel` applies the operations and removes a leaving row
   after `motion.base` (a Timer; 0 at Off removes at once). A key that comes
   back while leaving is revived in place. `fresh` is false for the first sync
   so startup does not animate.
4. **`RowSlot.qml`** (new): wraps every row element; width = item width ×
   `appear`, content scale `0.6 + 0.4 × appear` and opacity `appear` (Reduced:
   opacity only; Off: instant). Used for pinned apps and groups, running apps,
   minimized tiles, folders and buttons, drives. Tiles, folders/buttons and
   drives move to `KeyedListModel`. Delegates use `slot` for label slots,
   home centres and plate edges; `DockDragLogic` and gap lookups skip leaving
   rows. Pinning a running app = exit from the running run + entry in the
   pinned run; group create/ungroup likewise.
5. **Dividers**: width Behavior gated by `motion.layout`; visible while width >
   0.5 (as `DropGap`), so a split panel narrows to nothing instead of vanishing.
   `DockCard.qml` (774 lines) moves the right group (folders, buttons, drives,
   their dividers) into its own component to stay under 800.
6. **Popups**: `PopupLife.qml` (new, TooltipLife pattern) keeps the popup
   window alive until its fade ends. On close the body is frozen into a
   `ShaderEffectSource` (live: false) because the menu's state (e.g.
   `contextAppId`) clears at once; the frozen image fades/rises out. The three
   LazyLoaders in `Dock.qml` change only their `active` lines. Autohide fades
   popups too.
7. **Marks and badge**: `DockIndicatorRow` keeps a leaving mark for
   `motion.base` (shown count lags the target by the leaving one); new marks
   grow from 0. `BadgeMark` stays alive while its level > 0 (scale + fade), its
   width eases on digit changes.
8. **Unification**: every `duration:` in the dock's QML reads `root.motion`
   (or a component's `motion` property passed from it); one-shot effects check
   `motion.oneShots`; label reveal checks `motion.reveal`.

## Known limit

For the 180 ms of an exit, wave home centres computed from data (without the
leaving item) can differ from the drawn ones by part of the leaving item's
width; visible only with the pointer over the dock at that moment.

## Testing

- Unit: `DockMotion.plan` / `normalizeLevel`; `DockKeys.diff` (leave, revive,
  move, insert, slots, fresh/initial); a static test that QML `duration:`
  values in components come from `motion` (allow-list for the one-shot
  effects' own timings).
- Live: toggle `showAppsButton` through the config (a real row entry/exit) and
  capture a grim burst: card width changes over ~180 ms at Full, in one frame
  at Off, fade without width change at Reduced. Context menu open/close
  through a temporary IPC function, frames before/after close. Marks with
  `tests/live/indicators.sh` (opens terminal windows; ask the user first).
- `tests/run-all.sh`, CI-equivalent checks, `structure-check.py` (Dock.qml
  ceiling, 800-line cap).
- The user tests clicks and drags during animations, pin/unpin, groups,
  minimize to tiles, drives.
