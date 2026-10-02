# Repeatable performance benchmarks — design

Date: 2026-10-02. Status: approved in conversation, awaiting spec review.
Part 1 of 4 (benchmarks → performance → tests → security). Lives on the fork
(`priard`) first; may be offered upstream once it has proved useful.

## Goal

One command that measures the dock's CPU, RAM and VRAM cost in fixed
scenarios, writes a report that records the hardware and conditions, and
compares two reports. It is the yardstick for the performance work (part 2):
every optimisation PR quotes a before/after comparison from it.

## Constraints

- The dock shares the `quickshell` process with the Omarchy bar, background
  and notifications, so its cost can only be isolated by difference (plugin
  disabled vs enabled).
- No clicks and no synthetic keyboard input, ever. Pointer moves via
  `hyprctl dispatch 'hl.dsp.cursor.move({x=X, y=Y})'` (logical coords) are
  allowed; the pointer is restored afterwards.
- The script must leave the desktop as it found it, also on Ctrl-C or error
  (`try/finally`): pointer position, settings closed, `omadock.json`,
  `shell.json` (plugin order) and the plugin enabled.

## Baseline measured during design (2026-10-02, fresh shell restart)

| variant | quickshell RSS | VRAM (nvidia-smi) | omadock layer |
|---|---|---|---|
| plugin disabled | ~858 MB | 496 MiB | — |
| dock as today | ~896 MB | 690 MiB | 5120x1404 |
| dock, layer height 420 | ~890 MB | 558 MiB | 5120x420 |

Idle CPU of the whole process: ~1.25 % with the dock, ~1.1 % without.
After several hours of uptime the process was at 1.05 GB RSS (fresh:
0.89 GB), with or without the dock, so a soak scenario is worth having.

## Command line

```
tests/bench/bench.py run [--full] [--events] [--repeat N] [--yes] [--out DIR]
tests/bench/bench.py compare A.json B.json
```

- `run` (quick mode): no restarts, scenarios S0–S4 on the live shell.
- `--full`: additionally restarts the shell and measures S0 with the plugin
  disabled and enabled (absolute dock cost). Asks for confirmation unless
  `--yes`.
- `--events`: adds S5 (workspace switching), which changes the visible
  workspace, so it is opt-in.
- `--repeat N` (default 3): each scenario runs N times; the report keeps the
  median and the spread.
- Results go to `bench/results/<YYYY-MM-DD-HHMM>-<host>.json` plus a short
  Markdown summary printed to stdout. Result files are committed on `priard`
  as history.

## Metrics

Sampled every 250 ms from `/proc/<quickshell pid>`, VRAM every 1 s
(`nvidia-smi` is slow, ~50 ms per call):

- RSS (`VmRSS`) and PSS (`smaps_rollup`)
- VRAM: quickshell's row in `nvidia-smi --query-compute-apps`, falling back
  to parsing the process table of `nvidia-smi`
- CPU %: `utime+stime` delta over the window, **per thread**
  (`/proc/<pid>/task/*/stat`), reported as main (QML/GUI) thread, render
  thread(s) and the rest; a waking render thread at idle means something
  animates in the background
- Hyprland's CPU % over the same window (the compositor pays for redrawing
  and blurring our surface)
- thread count and open fd count (growth = leaked processes or pipes)
- context switches (`voluntary_ctxt_switches`) per second as a wake-up proxy

## Scenarios

| # | scenario | duration | measures |
|---|---|---|---|
| S0 | idle, pointer far from the dock | 30 s | baseline CPU, memory |
| S1 | pointer sweeps across every dock item and back, looped | 30 s | hover effects, tooltips, compositor cost |
| S2 | tooltip of an app with ≥2 windows (window previews) | 15 s | capture VRAM and CPU |
| S3 | settings open (`openSettings`), then `closeSettings` | 15 s | settings panel cost |
| S4 | idle again after S1–S3 | 30 s | memory/fd return to S0 level (leaks) |
| S5 | `--events`: 20 switches between two workspaces, then back | ~20 s | CPU per event |
| S6 | urgent window present (optional, if one is found) | 15 s | urgent animation cost |
| full | `--full`: S0 after restart, plugin disabled vs enabled | 2x30 s | absolute dock cost |

S2 is skipped with a note in the report when no app has two windows; S6 is
skipped when no urgent window exists (the script does not create one).

## How the script finds dock items

The omadock layer covers most of the screen, so item positions cannot be
read from `hyprctl layers`. A new **read-only** IPC function in
`DockHost.qml`:

```
omarchy-shell omadock itemGeometry  → JSON [{id, kind, x, y, w, h, windows}, …]
```

Logical screen coordinates, ready for `cursor.move`. It changes nothing and
is also used by the live tests. After the popup refactor (part 2) the dock
window shrinks, and the function keeps returning screen coordinates.

## Flow of one run

1. Check preconditions: quickshell running, omadock layer mapped, IPC target
   present. Wait until the 1-minute load average drops below a threshold
   (warn and record it if it does not within 30 s).
2. Record conditions: CPU model, GPU and driver, RAM, `pacman -Q omarchy
   quickshell hyprland qt6-base`, dock git commit and dirty flag, sha256 of
   `omadock.json`, number of pinned items and open windows, monitor
   resolution and scale, uptime of the quickshell process.
3. Back up pointer position (`hyprctl cursorpos`), and for `--full` the
   `shell.json`.
4. `reveal` via IPC if autohide is on; enter the dock from outside
   (y ≈ 1250) so hover-enter effects fire.
5. Run the scenarios with a sampler thread.
6. `finally`: restore pointer, `closeSettings`, re-enable the plugin and
   restore `shell.json` if they were touched, restart if needed, run
   `tests/smoke-test.sh`.

## Compare

`compare A.json B.json` prints, per scenario and metric, A, B, absolute and
relative difference, and flags differences smaller than the measured spread
as noise. It warns when the recorded conditions differ (hardware, versions,
config hash).

## Files

```
tests/bench/bench.py      # run / compare, stdlib only
tests/bench/README.md     # how to run, what the numbers mean, caveats
bench/results/*.json      # committed history (fork only)
DockHost.qml              # + itemGeometry()
```

## Out of scope

Frame timing (QSG_RENDER_TIMING / QML profiler) is used ad hoc while
optimising, not as part of the repeatable benchmark.
