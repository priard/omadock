# omadock — fork `priard`

Fork of https://github.com/thepathless/omadock (remote `upstream`); pushed
to https://github.com/priard/omadock (remote `fork`). No `origin`, so
`omarchy plugin update` leaves it alone.

Sync: `git fetch upstream && git merge upstream/main && git push fork priard`
(`main` is upstream's stable branch; it gets release batches from
`experimental`).

## Workflow

- `main` and `experimental` on the fork mirror upstream's.
- Upstream takes PRs against `experimental` only (CI enforces it). Feature
  work goes on `feat/*` branches cut from `upstream/experimental`, then
  gets merged into `priard`.
- `priard` is what runs locally: upstream plus unmerged feature branches.

## Upstreamed

- #12 settings panel, background/shadow/border switches (merged 2026-09-29).
- #13 dock polish, stacks, icon styles, blur/shadow controls (landed in v4.0.0).
- #14 split panels, folder and group reordering, drag improvements, drive
  section (merged 2026-10-02).
- #15-#25 merged 2026-10-03: file drag-out, ungroup/unpin, dividers,
  presets, hover effects, keep-pointer, wheel pacing, window previews,
  hardening, perf fixes, popup windows (dock VRAM 194 -> 26 MiB).

- #26 tooltip fade, linger and cross-fade (merged 2026-10-03).

- #27-#33 and #36 integrated into `experimental` 2026-10-04 and released
  in v4.0.1: notification urgency without the shell service, badge follows
  hover effects, CI security grep and shader check, stack limits, unsafe
  drive removal warning, more unit tests, live tooling and the benchmark,
  preset menu flicker.

- #40 settings pages got a null root (v4.0.1 regression), #41 group tile
  keeps its 2x2 shape with one or two members: merged into `experimental`
  2026-10-04, released in v4.0.3.

- #42 omadock as the notification sender, #44 theme re-read on every
  switch, #45 rim over a gradient fill, #46 badge placed by x/y: merged
  2026-10-05/07, on upstream `main` with the Dock.qml split and labels.

## Open

- #47 side labels (`feat/side-labels`), opened 2026-10-07.
- #49 panel layout and Both sides alignment (`feat/panel-layout`, cut
  from `feat/side-labels`, depends on #47), opened 2026-10-07.

## Not upstream yet

- `feat/side-labels`: names beside the icons (always, or over the
  neighbours on hover), readable auto colour, pill/plate backgrounds with
  corner options, indicator column on plates, tooltips only when they add
  something, Labels settings page, in-place Rename in the right-click
  menu for apps, groups and folders, icon block centred vertically.
- `feat/panel-layout`: Dock / Panel layout (full-width bar on the bottom
  edge) and the Both sides alignment (apps left, folders and drives
  right), `setLayout` IPC.

## Fork only

- `bench/results/` history, `tests/run-all.sh` with the qmllint baseline
  and manifest checks (`tests/README.md`). The benchmark, live tests and
  IPC `itemGeometry()` / `state()` are upstream since v4.0.1.
