# OmaDock tests

    tests/run-all.sh            # offline: unit + static, ~10 s, safe anytime
    tests/run-all.sh --live     # against the running shell
    tests/run-all.sh --all      # both

Benchmarks live in `tests/bench/` (see its README).

## Offline tier

Touches nothing outside temporary directories.

| file | covers |
|---|---|
| `unit/dockmodel.test.mjs` | regression tests for the hardening fixes: real arrays only, malformed config not overwritten, blur/sound/folder bounds, dropped paths |
| `model.test.js`, `test_helpers.py` | the upstream author's own tests (DockModel helpers, script helpers) |
| `unit/dockmodel-core.test.mjs` | pinning, grouping, app matching, notification domains, presets and look bounds |
| `unit/test_list_folder.py` | stack listing: sorting, limits, hidden files, non-UTF-8 names, preview whitelist, 20 000 entry budget |
| `unit/test_list_drives.py` | drive listing from lsblk JSON: skips, nesting, dedupe, icons, label cleanup |
| `unit/test_eject_drive.py` | eject fallback order, missing tools, notification text sanitised |
| `unit/test_drop_check.py` | MIME matching for files dropped on app icons |
| `unit/test_capped_gate.sh` | the CappedFileView read gate: FIFO, directory, /dev/zero, oversize |
| `static/shaders-in-sync.sh` | committed `.qsb` equal the compiled `.frag` sources |
| `static/manifest.sh` | manifest fields and `omarchy plugin validate` |
| `static/qmllint.sh` | Qt 6 qmllint, compared with `qmllint-baseline.json` |
| `static/security_grep.py` | rich text, eval, shell concatenation, `hyprctl eval`, `notify-send`, inline python, Text without PlainText; compared with `security-baseline.json` |
| `bench/test_bench.py` | benchmark helpers |

JS tests load `DockModel.js` into a `node:vm` context (it uses no Qt
globals); `DOCKMODEL=path` tests another copy. Python tests use the
standard library only.

## Live tier

Needs the Omarchy shell running with the plugin enabled. Backs up
`~/.config/omarchy/omadock.json` and restores it on exit. Never clicks or
types.

| file | covers |
|---|---|
| `smoke-test.sh` | layer mapped, IPC target registered, no QML errors in the log |
| `live/ipc-roundtrip.sh` | every IPC function, asserted through `state()` |
| `live/config-fuzz.sh` | eleven malformed configs: dock stays up, file never rewritten |

Do not use the computer while the live tier runs: the settings panel is a
full-screen overlay that takes keyboard focus and closes on any click or
Escape, which fails the IPC test.

Quickshell reloads the plugin whenever a file in its directory changes
(a commit, `__pycache__`, an editor's swap file); the dock is gone for
about half a second. The live tests wait for it (`live/common.sh`), and
`run-all.sh` sets `PYTHONDONTWRITEBYTECODE=1`.

`launch-harness.py` (every installed desktop id resolves the way
`launch()` builds it) is run by hand: it also fails on hidden local
desktop overrides that GIO cannot resolve, which is a property of the
system, not of the dock.

## Not automated

Clicks, drags (reordering, file drops, drag-out), opening stacks, ejecting
a drive, sound playback and visual appearance. These are checked by hand
after changes to the code involved.

## Baselines

After a reviewed change that adds a qmllint warning or a new
`hyprctl eval` / `notify-send` call site:

    tests/static/qmllint.sh --update
    python3 tests/static/security_grep.py --update

and commit the baseline with the change. Shaders: recompile with
`/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o X.qsb X`.
