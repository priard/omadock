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

## Open

- none.

## Fork only

- `bench/results/` history, `tests/run-all.sh` with the qmllint baseline
  and manifest checks (`tests/README.md`). The benchmark, live tests and
  IPC `itemGeometry()` / `state()` are upstream since v4.0.1.
