# Test suite and test documentation — design

Date: 2026-10-02. Status: approved in conversation, awaiting spec review.
Part 3 of 4. Test infrastructure stays on the fork first; the bug fixes it
drives and the script extractions go upstream in `feat/hardening` (shared
with part 4).

## Goal

A test suite with a fast offline tier that anyone can run before a commit,
a live tier that exercises the running dock safely, and a `tests/README.md`
that says how to run them, what is covered and what is deliberately not.

## Tooling facts

- `/usr/bin/qmllint`, `qmltestrunner`, `qml` are Qt 5. Use
  `/usr/lib/qt6/bin/{qmllint,qsb}` (Qt 6.11).
- node 26 (`node:test` built in) and python 3.14 with `gi` are available;
  pytest is not, so Python tests use `unittest`.
- `DockModel.js` uses no Qt globals and loads unchanged in node through
  `vm.runInContext`, exposing its functions.
- `qsb` output is deterministic: recompiling the five `.frag` files gives
  byte-identical `.qsb` files today.

## Layout

```
tests/run-all.sh                   # --offline (default) | --live | --all; non-zero on any failure
tests/README.md
tests/unit/dockmodel.test.mjs      # node --test
tests/unit/test_list_folder.py     # python3 -m unittest
tests/unit/test_drop_check.py
tests/unit/test_list_drives.py     # + fixtures/lsblk-*.json
tests/unit/test_eject_drive.py     # fake binaries on PATH
tests/unit/test_capped_gate.sh
tests/static/shaders-in-sync.sh
tests/static/qmllint.sh + qmllint-baseline.json
tests/static/manifest.sh
tests/static/security-grep.sh      # see part 4
tests/live/smoke-test.sh           # moved from tests/
tests/live/ipc-roundtrip.sh
tests/live/config-fuzz.sh
tests/launch-harness.py            # unchanged (system tier)
```

Offline tier: seconds, touches nothing outside temp dirs. Live tier: only
with `--live`; backs up `omadock.json` and restores it with `trap`; no
clicks, no keyboard; pointer moves only where needed, restored after.

## Code changes that enable testing

- Extract the inline Python in `Dock.qml` for drive listing (~1288) and
  eject (~1327) into `scripts/list-drives.py` and `scripts/eject-drive.py`,
  called with argv only. `list-drives.py` exposes a `walk(lsblk_json)`
  function tested with fixtures; `statvfs` is stubbed.
- Move `applyLook` (`Dock.qml:2082-2152`: clamping and migrations) into
  `DockModel.js` as a pure `parsed -> look` function used by `Dock.qml`.
- Read-only IPC `state()` in `DockHost.qml` returning JSON (dock visible,
  settings open, active preset, item count), next to `itemGeometry()` from
  part 1.

## Test cases, by value

1. Known bugs (red first, then fixed in `feat/hardening`):
   - array-like objects with a huge `length` in `toArray`/`boundList`/
     `parsePinned` (`DockModel.js:32-41, 283, 353-362`) freeze the shell;
     require real arrays as `boundPresets` already does;
   - `list-folder.py` crashes on a non-UTF-8 file name (`quote_segment`,
     l.100) and prints no JSON; must still print valid JSON with the entry;
   - a malformed `omadock.json` followed by any save (settings change,
     `setAlignment`, `setPosition`, `applyPreset`) rewrites the file from
     `{}` and drops keys (`saveConfig`, `Dock.qml:3513-3524`); fix: when the
     file on disk does not parse to an object, skip the write and log a
     warning.
2. Config bounding: `readCapped`, `boundAppGroups`, `boundPinnedFolders`,
   `boundPresets`, `cleanPresetName`, `pickLook`, `lookIncludes`, and the
   extracted `applyLook` (clamps, migrations, `Infinity`, wrong types).
3. Pinning and grouping: `parsePinned`, `serializePinned`, `togglePinned`,
   `reorderPinned`, `moveBefore`, `pinnedRow`, `rowState`, `ungroupRow`,
   `reanchorGroups`.
4. App matching: matrix for `stripDesktop`, `getCandidates`, `isAppMatch`,
   `findNotificationTargets`, `extractNotificationWebDomain`; `buildEntries`
   with mock toplevels; icon resolvers with a stub app library.
5. Static: shaders in sync (recompile to temp, `cmp`), qmllint against a
   committed baseline (filtering the `unqualified`/`import` noise; only new
   categories or higher counts fail), manifest parses and
   `omarchy plugin validate` passes.
6. Scripts: `list-folder.py` sort keys and natural sort, hidden entries,
   limit clamping, missing/unreadable folder, newline names, symlinks,
   thumbnail cache via `XDG_CACHE_HOME`, 10k-file time budget;
   `drop-check.py` argument cases and `supported()` wildcards/inheritance;
   `list-drives.py` skip list, nested children, dedup, icon choice;
   `eject-drive.py` fallback order and label sanitising; the
   `CappedFileView` gate (FIFO, directory, symlink to `/dev/zero`,
   oversize).
7. Live: every IPC function round-trip (`openSettings`, each
   `openSettingsPage`, `closeSettings`, `toggleVisibility` twice,
   `applyPreset` unknown → "not found", `state()` consistent); config fuzz
   (empty, `garbage{`, `null`, `[]`, `"str"`, `1e999`, wrong types, 2 MB)
   asserting layer still mapped, log clean and the file left untouched.
   The smoke test reads more than the last 30 log lines and filters by
   time since the test started.

## README contents

How to run each tier and prerequisites; what each file covers; what is not
tested automatically and why (clicks, drags, playback, visual look: tested
by hand by the user); safety notes for the live tier; how to update the
qmllint baseline and recompile shaders.
