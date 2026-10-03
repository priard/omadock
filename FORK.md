# omadock — fork `priard`

Fork of https://github.com/thepathless/omadock (remote `upstream`); pushed
to https://github.com/priard/omadock (remote `fork`). No `origin`, so
`omarchy plugin update` leaves it alone.

Sync: `git fetch upstream && git merge upstream/main && git push fork priard`

## Workflow

- `main` on the fork mirrors `upstream/main`.
- Feature work goes on `feat/*` branches cut from `upstream/main`, so they
  can be sent upstream as PRs, then merged into `priard`.
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

## Open

- #27 urgency on notifications through the popup-file watch (`feat/notification-urgency`).
- #28 notification badge follows the icon's hover effects (`feat/badge-follows-icon`).
- #29 CI: security grep and shader source check (`feat/ci-static-checks`).
- #30 stacks: "20000+" and "Folder could not be read" (`feat/stack-limits`).
- #31 warn when a drive is pulled out while mounted (`feat/unsafe-removal`).

## Fork only

- `tests/bench/` benchmark, `bench/results/` history, `tests/run-all.sh`
  with static checks and live tests (`tests/README.md`).
- IPC `itemGeometry()` and `state()` for the benchmark and live tests.
