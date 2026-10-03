# Hardening and Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the security and robustness findings with regression tests (upstream PR `feat/hardening`), and give the fork an offline + live test suite with a README.

**Architecture:** Part A works on branch `feat/hardening` (cut from `upstream/main`) in a separate git worktree, so the live dock is untouched until the branch is merged into `priard`. Fixes move logic into pure, testable places: `DockModel.js` helpers (tested with `node --test` by loading the file into a `vm` context) and standalone scripts in `scripts/` (tested with `unittest`). Part B works on `priard` and adds the runner, static checks, broader unit tests and live tests.

**Tech Stack:** Node 26 (`node:test`, `node:vm`), Python 3.14 stdlib `unittest`, Qt 6 tools in `/usr/lib/qt6/bin` (`qsb`, `qmllint`), bash, Quickshell IPC.

**Spec:** `docs/superpowers/specs/2026-10-02-tests-design.md` and `docs/superpowers/specs/2026-10-02-security-design.md`

## Global Constraints

- The live checkout is `~/.config/omarchy/plugins/omadock` on branch `priard`; every file change there affects the running desktop. Part A happens in the worktree `~/.local/share/omadock-wt/hardening` (never inside `~/.config/omarchy/plugins/`, or Omarchy would load it as a plugin).
- Before merging anything into `priard`: `git merge-tree --write-tree priard <branch>` must report no conflicts (conflict markers in QML stop the dock loading).
- After any QML change in the live checkout: `omarchy restart shell; sleep 8; bash tests/smoke-test.sh` must print `SMOKE TEST PASSED`, and `journalctl --user --since "-30 s" | grep -iE "omadock/"` must show no new errors.
- Never synthesise keyboard input; no clicks. Clicking, dragging, ejecting a drive and opening stacks are tested by the user.
- Never commit `CLAUDE.md`, `FORK.md`, `docs/superpowers/` or the manifest version bump to `feat/hardening` or `feat/window-previews`.
- English in code, comments and commits; no AI attribution; one topic per commit with a body explaining why.
- Use `/usr/lib/qt6/bin/qmllint` and `/usr/lib/qt6/bin/qsb`; `/usr/bin/qmllint` is Qt 5. pytest is not installed; use `unittest`.
- Opening the upstream PR (`gh pr create`) needs the user's explicit go-ahead; pushing `feat/hardening`, `priard` and `feat/window-previews` to `fork` is covered by approving this plan (pushing `feat/window-previews` updates the open PR #22).

## Rulings against the spec (made while planning)

- **No `applyLook` extraction.** `applyLook` differs heavily between `upstream/main` and `priard` (presets, dividers, hover effects); moving it in `feat/hardening` would conflict with every open PR. The two values the spec wanted tested through it get small pure helpers instead (`boundSystemBlurSize`, `cleanSoundName`).
- **No new `windowPreviews` key.** Upstream already has a "Window previews" switch (`advancedTooltips`, default on). PR #22 only gets the README disclosure.
- **`tests/smoke-test.sh` stays where it is.** CLAUDE.md, the benchmark and habits call it by that path.
- **Regression tests for the fixes ship in the PR** (`tests/unit/` with stdlib-only tests). The runner, static checks, live tests and README stay on the fork, as agreed.
- **`toArray` keeps accepting array-likes**: QML list values are array-like, and the dock passes them in. Only config-facing functions (`boundList`, `parsePinned`) require real arrays.

## Review Focus

- `saveConfig` after the array fix: `root.appGroups` / `root.pinnedFolders` must still be real JS arrays inside QML, or every save would write empty groups/folders. Verified live in Task 7 (save, then compare `appGroups` and `pinnedFolders` in the file).
- A malformed `omadock.json` must survive a settings change untouched. Verified live in Task 7 and by `config-fuzz.sh` (Task 11).
- Drive label with markup or 10 KB of text must not reach `notify-send` raw, and a missing `gio`/`udisksctl` must not crash eject. Tested in Task 6 (`test_eject_drive.py`).
- Folder with 20 000+ entries or a non-UTF-8 name must still give valid JSON quickly. Tested in Task 5.
- A dropped path containing a newline must not become two pins. Tested in Task 4.

---

## File Structure

Part A (`feat/hardening`, worktree):
```
DockModel.js                      # boundList/parsePinned real arrays; configBase; boundSystemBlurSize;
                                  # cleanSoundName; absolute folder paths; localPathsFromUrls
Dock.qml                          # saveConfig skip on malformed; helpers wired; scriptPath(); drive scripts;
                                  # timeout around list-folder.py
components/SettingsPanel.qml      # group name maximumLength
scripts/list-folder.py            # non-UTF-8 names, preview whitelist, scan budget
scripts/drive_label.py            # clean_label() shared by the drive scripts
scripts/list-drives.py            # was inline python in Dock.qml
scripts/eject-drive.py            # was inline python in Dock.qml
tests/unit/dockmodel.test.mjs     # regression tests for the DockModel fixes
tests/unit/test_list_folder.py
tests/unit/test_list_drives.py
tests/unit/test_eject_drive.py
```
Part B (`priard`):
```
tests/run-all.sh
tests/README.md
tests/unit/dockmodel-core.test.mjs   # characterization tests (pinning, grouping, matching, presets)
tests/unit/test_drop_check.py
tests/unit/test_capped_gate.sh
tests/static/shaders-in-sync.sh
tests/static/manifest.sh
tests/static/qmllint.sh, qmllint_summary.py, qmllint-baseline.json
tests/static/security_grep.py, security-baseline.json
tests/live/ipc-roundtrip.sh
tests/live/config-fuzz.sh
DockHost.qml                         # + state() IPC
```

---

## Part A — `feat/hardening`

### Task 1: Worktree, DockModel test harness, real arrays only for config lists

**Files:**
- Create: `tests/unit/dockmodel.test.mjs`
- Modify: `DockModel.js` (`boundList`, `parsePinned`)

**Interfaces:**
- Produces: test loader pattern `const M = vm.createContext({}); vm.runInContext(src, M)` with `plain()` to copy cross-realm values; later tasks append tests to this file.
- `boundList(arr, max, predicate)` returns `[]` for anything that is not `Array.isArray`. `parsePinned(raw)` reads only a real array (top level or `.pinned`).

- [ ] **Step 1: Create the worktree and branch**

```bash
cd ~/.config/omarchy/plugins/omadock
git fetch upstream
mkdir -p ~/.local/share/omadock-wt
git worktree add -b feat/hardening ~/.local/share/omadock-wt/hardening upstream/main
cd ~/.local/share/omadock-wt/hardening && git log --oneline -1
```
Expected: the worktree exists at `upstream/main` (`51c5e13` or newer).

- [ ] **Step 2: Write the failing tests** — `tests/unit/dockmodel.test.mjs`

```js
// Regression tests for DockModel.js. The file is plain JS with no Qt
// globals, so it runs in a vm context; DOCKMODEL overrides the path.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
// Values from the vm realm have foreign prototypes; compare plain copies.
const plain = (v) => JSON.parse(JSON.stringify(v))

test("boundAppGroups ignores array-like objects", () => {
  assert.deepEqual(plain(M.boundAppGroups({ length: 1, 0: { id: "g" } })), [])
})

test("boundAppGroups keeps real arrays", () => {
  assert.equal(M.boundAppGroups([{ id: "g", apps: ["a"] }]).length, 1)
})

test("group apps must be a real array", () => {
  const g = M.boundAppGroups([{ id: "g", apps: { length: 1, 0: "a" } }])
  assert.deepEqual(plain(g[0].apps), [])
})

test("boundPinnedFolders ignores array-like objects", () => {
  assert.deepEqual(plain(M.boundPinnedFolders({ length: 1, 0: { path: "/tmp" } })), [])
})

test("parsePinned ignores array-like pinned lists", () => {
  assert.deepEqual(plain(M.parsePinned('{"pinned": {"length": 1, "0": "a"}}')), [])
  assert.deepEqual(plain(M.parsePinned('{"length": 1, "0": "a"}')), [])
})

test("parsePinned keeps real lists, deduped and without .desktop", () => {
  assert.deepEqual(plain(M.parsePinned('{"pinned": ["a.desktop", "b", "a"]}')), ["a", "b"])
  assert.deepEqual(plain(M.parsePinned('["x"]')), ["x"])
})

test("a huge claimed length returns at once", () => {
  const t0 = performance.now()
  M.boundAppGroups({ length: 1e7 })
  M.parsePinned('{"pinned": {"length": 10000000}}')
  assert.ok(performance.now() - t0 < 50, `took ${performance.now() - t0} ms`)
})
```

- [ ] **Step 3: Run to verify it fails**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: FAIL in "ignores array-like objects", "group apps must be a real array", "ignores array-like pinned lists" and "a huge claimed length returns at once"; "keeps real arrays/lists" PASS.

- [ ] **Step 4: Implement** — in `DockModel.js`

Replace `boundList`:

```js
// Shape-bound generic list: keeps at most `max` entries that pass `predicate`.
// Real arrays only: JSON gives nothing else, and an array-like object
// ({ "length": 1e9 }) would be walked to its claimed length.
function boundList(arr, max, predicate) {
  if (!Array.isArray(arr)) return []
  var out = []
  for (var i = 0; i < arr.length && out.length < max; i++) {
    var v = arr[i]
    if (predicate(v)) out.push(v)
  }
  return out
}
```

In `parsePinned` replace the `var arr = isList(parsed) ...` line with:

```js
  // Real arrays only (see boundList).
  var arr = Array.isArray(parsed) ? parsed : (Array.isArray(parsed.pinned) ? parsed.pinned : [])
```

- [ ] **Step 5: Run to verify it passes**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: 7 tests pass.

- [ ] **Step 6: Commit**

```bash
git add DockModel.js tests/unit/dockmodel.test.mjs
git commit -m "fix(config): accept only real arrays for persisted lists

boundList and parsePinned walked any object with a numeric length, so a
config holding {\"appGroups\": {\"length\": 1e9}} (well under the 1 MiB
read cap) froze the shell. JSON only ever yields real arrays, so array-
likes are now rejected, as boundPresets already does. Adds node:test
regression tests that load DockModel.js in a vm context."
```

---

### Task 2: Keep a malformed config intact on save

**Files:**
- Modify: `DockModel.js` (new `configBase`), `Dock.qml` (`saveConfig`)
- Test: `tests/unit/dockmodel.test.mjs`

**Interfaces:**
- Produces: `configBase(text: string) -> object | null` — `{}` for empty text, the parsed object, or `null` when the text is not a JSON object.

- [ ] **Step 1: Write the failing tests** (append)

```js
test("configBase: empty text starts from an empty object", () => {
  assert.deepEqual(plain(M.configBase("")), {})
  assert.deepEqual(plain(M.configBase("   \n")), {})
})

test("configBase: a JSON object is kept", () => {
  assert.deepEqual(plain(M.configBase('{"a": 1, "b": [2]}')), { a: 1, b: [2] })
})

test("configBase: anything else means do not write", () => {
  for (const t of ["garbage{", "[]", "[1]", '"str"', "null", "42", "true"])
    assert.equal(M.configBase(t), null, t)
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: the three `configBase` tests FAIL with `M.configBase is not a function`.

- [ ] **Step 3: Implement**

In `DockModel.js`, after `readCapped`:

```js
// The object saveConfig merges the dock's keys into: {} for an empty file,
// the parsed object otherwise, and null when the file holds anything else
// (a typo, an array, a string). null means "do not write": rewriting from
// {} would silently drop every key the dock does not own.
function configBase(text) {
  var t = String(text == null ? "" : text).trim()
  if (!t) return {}
  var parsed
  try {
    parsed = JSON.parse(t)
  } catch (e) {
    return null
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  return parsed
}
```

In `Dock.qml` `saveConfig()`, replace

```qml
    var conf = {}
    try {
      var txt = DockModel.readCapped(configFile.text, DockModel.MAX_CONFIG_BYTES).trim()
      if (txt) conf = JSON.parse(txt) || {}
    } catch (e) {
      conf = {}
    }
```

with

```qml
    var conf = DockModel.configBase(DockModel.readCapped(configFile.text, DockModel.MAX_CONFIG_BYTES))
    if (conf === null) {
      console.warn("[omadock] omadock.json is not a JSON object; not saving so its other keys survive. Fix the file to save settings again.")
      return
    }
```

- [ ] **Step 4: Run tests**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: 10 tests pass. Also `grep -n "configBase" Dock.qml` shows the new call.

- [ ] **Step 5: Commit**

```bash
git add DockModel.js Dock.qml tests/unit/dockmodel.test.mjs
git commit -m "fix(config): do not overwrite a malformed omadock.json

saveConfig started from {} when the file did not parse, so one typo in
omadock.json followed by any settings change (or the setAlignment,
setPosition IPC) rewrote the file with only the dock's keys. It now
skips the write and logs a warning until the file is fixed."
```

---

### Task 3: Bounds for blur size, sound name and pinned folder paths

**Files:**
- Modify: `DockModel.js` (`boundSystemBlurSize`, `cleanSoundName`, `boundPinnedFolders`), `Dock.qml` (loadConfig, `setUrgentSoundName`, `setBlurSize`)
- Test: `tests/unit/dockmodel.test.mjs`

**Interfaces:**
- Produces: `MAX_SYSTEM_BLUR_SIZE = 100`; `boundSystemBlurSize(v) -> int 0..100`; `cleanSoundName(v) -> string` (`"bell"` fallback); `boundPinnedFolders` keeps only paths starting with `/`, `~/` or equal to `~`.

- [ ] **Step 1: Write the failing tests** (append)

```js
test("boundSystemBlurSize clamps to 0..100", () => {
  assert.equal(M.boundSystemBlurSize(8), 8)
  assert.equal(M.boundSystemBlurSize(7.6), 8)
  assert.equal(M.boundSystemBlurSize(1e12), 100)
  assert.equal(M.boundSystemBlurSize(Infinity), 0)
  assert.equal(M.boundSystemBlurSize(-3), 0)
  assert.equal(M.boundSystemBlurSize("9"), 0)
})

test("cleanSoundName accepts theme sound ids and none", () => {
  assert.equal(M.cleanSoundName("message-new-instant"), "message-new-instant")
  assert.equal(M.cleanSoundName("none"), "none")
})

test("cleanSoundName rejects paths and junk", () => {
  for (const v of ["../../x", "/usr/share/a.oga", "Bell", "", "a".repeat(49), 5, null])
    assert.equal(M.cleanSoundName(v), "bell", String(v))
})

test("pinned folders must be absolute or home-relative", () => {
  const out = plain(M.boundPinnedFolders([
    { path: "/srv/a" }, { path: "~/b" }, { path: "~" }, { path: "-x" }, { path: "rel/c" }, { path: 5 },
  ]))
  assert.deepEqual(out.map((f) => f.path), ["/srv/a", "~/b", "~"])
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: 4 new tests FAIL (`not a function` for the first three, wrong paths for the last).

- [ ] **Step 3: Implement**

In `DockModel.js` next to the other ceilings:

```js
var MAX_SYSTEM_BLUR_SIZE = 100

// Hyprland's own blur size as remembered in the config: an integer in
// 0..MAX_SYSTEM_BLUR_SIZE (0 = not remembered). It is written back to
// decoration.blur.size, where a huge value stalls the compositor.
function boundSystemBlurSize(v) {
  if (typeof v !== "number" || !isFinite(v)) return 0
  return Math.max(0, Math.min(MAX_SYSTEM_BLUR_SIZE, Math.round(v)))
}

// A sound theme id for canberra-gtk-play -i, or "none"; anything else
// (a path, "../x") falls back to "bell".
function cleanSoundName(v) {
  return (typeof v === "string" && /^[a-z0-9][a-z0-9-]{0,47}$/.test(v)) ? v : "bell"
}
```

In `boundPinnedFolders`, replace the predicate's last line `return !!_boundedStr(f.path, MAX_FOLDER_PATH)` with:

```js
    // Absolute or home-relative only: the path reaches xdg-open, which has
    // no "--", so a relative "-x" would be read as an option.
    var p = _boundedStr(f.path, MAX_FOLDER_PATH)
    return !!p && (p.charAt(0) === "/" || p === "~" || p.indexOf("~/") === 0)
```

In `Dock.qml`:
- loadConfig: replace the `root.systemBlurSize = ...` line with
  `root.systemBlurSize = DockModel.boundSystemBlurSize(parsed ? parsed.systemBlurSize : 0)`
- loadConfig: replace the `root.urgentSoundName = ...` line with
  `root.urgentSoundName = DockModel.cleanSoundName(parsed ? parsed.urgentSoundName : "bell")`
- `setUrgentSoundName(name)`: make the first line `name = DockModel.cleanSoundName(name)`.
- `setBlurSize(size, currentSize)`: change `root.systemBlurSize = currentSize` to `root.systemBlurSize = DockModel.boundSystemBlurSize(currentSize)`.

- [ ] **Step 4: Run tests**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: 14 tests pass.

- [ ] **Step 5: Commit**

```bash
git add DockModel.js Dock.qml tests/unit/dockmodel.test.mjs
git commit -m "fix(config): bound blur size, sound name and folder paths

systemBlurSize had no upper limit and goes back into Hyprland's
decoration.blur.size; urgentSoundName was any string handed to
canberra-gtk-play; a pinned folder path could be relative, and a path
like -x reached xdg-open as an option. Each now has a pure, tested
bound in DockModel."
```

---

### Task 4: Dropped paths with line breaks

**Files:**
- Modify: `DockModel.js` (new `localPathsFromUrls`), `Dock.qml` (`localPathsFromUrls` delegates)
- Test: `tests/unit/dockmodel.test.mjs`

**Interfaces:**
- Produces: `DockModel.localPathsFromUrls(urls) -> string[]`.

- [ ] **Step 1: Write the failing tests** (append)

```js
test("localPathsFromUrls decodes file URLs", () => {
  assert.deepEqual(plain(M.localPathsFromUrls(["file:///home/u/a%20b", "https://x/y"])), ["/home/u/a b"])
})

test("localPathsFromUrls drops paths with line breaks", () => {
  assert.deepEqual(plain(M.localPathsFromUrls(["file:///tmp/a%0A/etc", "file:///tmp/b%0D"])), [])
})

test("localPathsFromUrls skips malformed escapes and relative paths", () => {
  assert.deepEqual(plain(M.localPathsFromUrls(["file:///bad%E0%A4%A", "file://host/x"])), [])
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: 3 new tests FAIL (`M.localPathsFromUrls is not a function`).

- [ ] **Step 3: Implement**

`DockModel.js`:

```js
// Local absolute paths from dropped file:// URLs. A path with a line break
// is dropped: the folder probes print one path per line, so "a\n/etc"
// would come back as two paths. Malformed escapes are skipped.
function localPathsFromUrls(urls) {
  var list = toArray(urls)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var u = String(list[i])
    if (u.indexOf("file://") !== 0) continue
    var p
    try {
      p = decodeURIComponent(u.slice(7))
    } catch (e) {
      continue
    }
    if (p.charAt(0) === "/" && !/[\r\n]/.test(p)) out.push(p)
  }
  return out
}
```

`Dock.qml`: replace the body of `function localPathsFromUrls(urls) { ... }` with `return DockModel.localPathsFromUrls(urls)` (keep the function so callers are unchanged).

- [ ] **Step 4: Run tests**

Run: `node --test tests/unit/dockmodel.test.mjs`
Expected: 17 tests pass.

- [ ] **Step 5: Commit**

```bash
git add DockModel.js Dock.qml tests/unit/dockmodel.test.mjs
git commit -m "fix(drop): ignore dropped paths that contain line breaks

The folder probes print dropped paths one per line, so a directory named
\"a<newline>/etc\" arrived as two paths and could pin a folder the user
never dragged. A malformed %-escape also threw out of the drop handler.
The conversion now lives in DockModel with tests."
```

---

### Task 5: `list-folder.py` — non-UTF-8 names, safe previews, scan budget

**Files:**
- Modify: `scripts/list-folder.py`, `Dock.qml` (folder stack command)
- Create: `tests/unit/test_list_folder.py`

**Interfaces:**
- Output gains `"truncated": bool`; `count` is capped at `MAX_SCAN` (20 000). `thumb` falls back to the original only for `.png/.jpg/.jpeg/.webp` ≤ 20 MiB.

- [ ] **Step 1: Write the failing tests** — `tests/unit/test_list_folder.py`

```python
"""scripts/list-folder.py, run as the dock runs it (a subprocess)."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "list-folder.py"


class ListFolder(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.base = pathlib.Path(tmp.name)
        self.dir = self.base / "f"
        self.dir.mkdir()
        self.env = dict(os.environ, XDG_CACHE_HOME=str(self.base / "cache"))

    def run_script(self, *args, folder=None):
        r = subprocess.run([sys.executable, str(SCRIPT), str(folder or self.dir), *args],
                           capture_output=True, timeout=120, env=self.env)
        return json.loads(r.stdout)

    def touch(self, name, size=1):
        p = self.dir / name
        p.write_bytes(b"\0" * size)
        return p

    def test_non_utf8_name_still_gives_json(self):
        with open(os.fsencode(str(self.dir)) + b"/bad\xff.png", "wb") as f:
            f.write(b"x")
        self.assertEqual(self.run_script()["count"], 1)

    def test_svg_and_gif_never_preview_the_original(self):
        self.touch("x.svg")
        self.touch("y.gif")
        self.assertEqual([i["thumb"] for i in self.run_script("name")["items"]], ["", ""])

    def test_small_png_previews_the_original(self):
        p = self.touch("a.png")
        self.assertEqual(self.run_script()["items"][0]["thumb"], str(p))

    def test_huge_png_has_no_preview(self):
        with open(self.dir / "big.png", "wb") as f:
            f.truncate(50 * 1024 * 1024)  # sparse, no disk use
        self.assertEqual(self.run_script()["items"][0]["thumb"], "")

    def test_cached_thumbnail_is_used_even_for_svg(self):
        p = self.touch("x.svg")
        uri = "file://" + urllib.parse.quote(str(p), safe="/!$&'()*+,;=:@-._~")
        d = self.base / "cache" / "thumbnails" / "large"
        d.mkdir(parents=True)
        t = d / (hashlib.md5(uri.encode()).hexdigest() + ".png")
        t.write_bytes(b"png")
        self.assertEqual(self.run_script()["items"][0]["thumb"], str(t))

    def test_scan_stops_at_budget(self):
        for i in range(20005):
            (self.dir / f"f{i}").touch()
        out = self.run_script("name", "5")
        self.assertEqual(out["count"], 20000)
        self.assertTrue(out["truncated"])
        self.assertEqual(len(out["items"]), 5)

    def test_small_folder_is_not_truncated(self):
        self.touch("a")
        self.assertFalse(self.run_script()["truncated"])

    def test_missing_folder_gives_valid_json(self):
        out = self.run_script(folder=self.base / "nope")
        self.assertEqual((out["count"], out["items"]), (0, []))

    def test_natural_name_sort_and_hidden_skipped(self):
        for n in ("a10", "a2", "A1", ".hidden"):
            self.touch(n)
        self.assertEqual([i["name"] for i in self.run_script("name")["items"]], ["A1", "a2", "a10"])

    def test_limit_is_clamped(self):
        for n in range(20):
            self.touch(f"f{n}")
        self.assertEqual(len(self.run_script("name", "abc")["items"]), 16)
        self.assertEqual(len(self.run_script("name", "-5")["items"]), 1)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest tests/unit/test_list_folder.py -v`
Expected: FAIL/ERROR in `test_non_utf8_name_still_gives_json` (JSONDecodeError: empty stdout), `test_svg_and_gif_never_preview_the_original`, `test_huge_png_has_no_preview`, `test_scan_stops_at_budget`, `test_small_folder_is_not_truncated` (KeyError `truncated`); the rest PASS.

- [ ] **Step 3: Implement** — `scripts/list-folder.py`

1. Docstring: replace the sentence about thumbnails with:
```
Hidden entries are skipped. At most MAX_SCAN visible entries are read
("truncated": true when the folder holds more). Each file carries "thumb":
a preview image path, preferring a freedesktop thumbnail a file manager
already rendered (~/.cache/thumbnails), then the file itself for small
PNG/JPEG/WebP images only (SVG and GIF are never decoded in the shell),
else "". The output is always valid JSON, even for a missing folder.
```
2. Constants after `MAX_LIMIT = 1000`:
```python
MAX_SCAN = 20000                      # entries read before giving up
PREVIEW_EXT = {".png", ".jpg", ".jpeg", ".webp"}
MAX_PREVIEW_BYTES = 20 * 1024 * 1024  # larger originals are not previewed
```
3. `quote_segment`:
```python
def quote_segment(segment):
    from urllib.parse import quote
    # Names that are not valid UTF-8 arrive as surrogate escapes; the URI
    # needs their raw bytes percent-encoded.
    return quote(segment.encode("utf-8", "surrogateescape"), safe="!$&'()*+,;=:@-._~")
```
4. In `main()`, replace the scan block (from `try:\n            scan = list(os.scandir(folder))` through the end of the `for entry in scan:` loop) with:
```python
    truncated = False
    if folder and os.path.isdir(folder):
        try:
            with os.scandir(folder) as scan:
                for entry in scan:
                    if entry.name.startswith("."):
                        continue
                    if len(entries) >= MAX_SCAN:
                        truncated = True
                        break
                    try:
                        st = entry.stat()
                        is_dir = entry.is_dir()
                    except OSError:
                        continue
                    ext = "" if is_dir else os.path.splitext(entry.name)[1].lower()
                    size = 0 if is_dir else st.st_size
                    entries.append({
                        "name": entry.name,
                        "path": entry.path,
                        "isDir": is_dir,
                        "isImage": ext in IMAGE_EXT,
                        "size": human_size(size),
                        "time": human_age(st.st_mtime),
                        "mtime": st.st_mtime,
                        "icon": icon_for(ext, is_dir),
                        "_ext": ext,
                        "_bytes": size,
                        "_ctime": st.st_ctime,
                    })
        except OSError:
            pass
```
(remove the old `if folder and os.path.isdir(folder):` header it replaces).
5. Thumb line:
```python
            previewable = e["_ext"] in PREVIEW_EXT and e["_bytes"] <= MAX_PREVIEW_BYTES
            item["thumb"] = thumbnail_for(e["path"]) or (e["path"] if previewable else "")
```
6. Output:
```python
    print(json.dumps({"count": len(entries), "items": items, "folder": folder,
                      "sort": sort, "truncated": truncated}))
```

`Dock.qml`: the folder stack `Process` command becomes
```qml
    command: ["timeout", "-k", "2", "10", "python3", decodeURIComponent(Qt.resolvedUrl("scripts/list-folder.py").toString().replace(/^file:\/\//, "")), folderStackScanner.targetFolder, folderStackScanner.sortKey, "300"]
```
with the comment above it extended by: `// timeout: a stalled filesystem (network mount) must not leave the helper running.`

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest tests/unit/test_list_folder.py -v`
Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/list-folder.py Dock.qml tests/unit/test_list_folder.py
git commit -m "fix(stacks): safe previews, non-UTF-8 names and a scan budget

Without a cached thumbnail the stack decoded the original file inside the
shell process, including SVG and GIF that any web page can drop into
~/Downloads; only small PNG/JPEG/WebP originals are previewed now. A
name that is not valid UTF-8 crashed the helper, leaving the stack
empty. A folder is read up to 20 000 entries and the helper runs under
a timeout."
```

---

### Task 6: Drive scripts out of `Dock.qml`, label sanitising, group name cap

**Files:**
- Create: `scripts/drive_label.py`, `scripts/list-drives.py`, `scripts/eject-drive.py`, `tests/unit/test_list_drives.py`, `tests/unit/test_eject_drive.py`
- Modify: `Dock.qml` (`removableDrivesScanner`, `ejectProc`, new `scriptPath`), `components/SettingsPanel.qml` (`nameField`)

**Interfaces:**
- `drive_label.clean_label(name, fallback="Drive") -> str` (≤ 64 chars, no `<>&`, controls or bidi marks).
- `list-drives.py`: `drives(data: dict, statvfs=os.statvfs) -> list[dict]` with keys `dev, name, mountpoint, size, space, fstype, icon` (same as before).
- `eject-drive.py`: `unmount(dev, mountpoint, run=subprocess.run) -> bool`; CLI `eject-drive.py DEV MOUNTPOINT NAME` prints `True`/`False`.
- `Dock.qml`: `function scriptPath(name) -> string` (local path of `scripts/<name>`).

- [ ] **Step 1: Write the failing tests**

`tests/unit/test_list_drives.py`:

```python
import importlib.util
import pathlib
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("list_drives", SCRIPTS / "list-drives.py")
list_drives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(list_drives)


class FakeStat:
    f_bavail, f_frsize, f_blocks = 1024, 1024 * 1024, 4096


def stat(mp):
    return FakeStat()


def dev(name, mp, **kw):
    d = {"name": name, "mountpoints": [mp], "rm": True, "type": "part", "size": "8G"}
    d.update(kw)
    return d


class Drives(unittest.TestCase):
    def test_usb_partition_listed(self):
        out = list_drives.drives({"blockdevices": [dev("sdb1", "/run/media/u/STICK", label="STICK", tran="usb")]}, stat)
        self.assertEqual(out[0]["dev"], "/dev/sdb1")
        self.assertEqual(out[0]["name"], "STICK")
        self.assertEqual(out[0]["icon"], "drive-removable-media-usb")
        self.assertEqual(out[0]["space"], "1.0 GB free of 4.0 GB")

    def test_system_mounts_and_fixed_disks_skipped(self):
        data = {"blockdevices": [dev("nvme0n1p2", "/", rm=False), dev("sda1", "/data", rm=False)]}
        self.assertEqual(list_drives.drives(data, stat), [])

    def test_children_walked_and_duplicates_dropped(self):
        child = dev("sdc1", "/media/x", fstype="ISO9660", rm=False)
        data = {"blockdevices": [{"name": "sdc", "mountpoints": [None], "children": [child, child]}]}
        out = list_drives.drives(data, stat)
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["icon"], "media-optical")

    def test_hostile_label_is_cleaned(self):
        out = list_drives.drives({"blockdevices": [dev("sdb1", "/run/media/u/x", label="<b>A&B</b>" + "z" * 200)]}, stat)
        self.assertNotIn("<", out[0]["name"])
        self.assertLessEqual(len(out[0]["name"]), 64)

    def test_statvfs_failure_leaves_space_empty(self):
        def boom(mp):
            raise OSError("gone")
        out = list_drives.drives({"blockdevices": [dev("sdb1", "/run/media/u/x")]}, boom)
        self.assertEqual(out[0]["space"], "")

    def test_junk_input(self):
        self.assertEqual(list_drives.drives([], stat), [])
        self.assertEqual(list_drives.drives({"blockdevices": "x"}, stat), [])


if __name__ == "__main__":
    unittest.main()
```

`tests/unit/test_eject_drive.py`:

```python
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("eject_drive", SCRIPTS / "eject-drive.py")
eject_drive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(eject_drive)
from drive_label import clean_label  # noqa: E402


class Result:
    def __init__(self, code):
        self.returncode = code


class Label(unittest.TestCase):
    def test_markup_removed(self):
        self.assertEqual(clean_label("<img src=x>&"), "img src=x")

    def test_long_label_capped(self):
        self.assertEqual(len(clean_label("a" * 10000)), 64)

    def test_bidi_and_controls_removed(self):
        self.assertEqual(clean_label("ab\u202ecd\x07\nef"), "abcd ef")

    def test_empty_falls_back(self):
        self.assertEqual(clean_label("  "), "Drive")
        self.assertEqual(clean_label(None, "USB Drive"), "USB Drive")


class Unmount(unittest.TestCase):
    def test_falls_back_in_order(self):
        calls = []

        def run(cmd, **kw):
            calls.append(cmd[0])
            return Result(0 if cmd[0] == "udisksctl" else 1)

        self.assertTrue(eject_drive.unmount("/dev/sdb1", "/run/media/u/x", run))
        self.assertEqual(calls, ["gio", "udisksctl"])

    def test_missing_tools_do_not_crash(self):
        def run(cmd, **kw):
            raise FileNotFoundError(cmd[0])

        self.assertFalse(eject_drive.unmount("/dev/sdb1", "/mnt/x", run))


class EndToEnd(unittest.TestCase):
    def test_notification_body_is_sanitised(self):
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = pathlib.Path(tmp)
            log = bin_dir / "notify.log"
            (bin_dir / "gio").write_text("#!/bin/sh\nexit 0\n")
            (bin_dir / "notify-send").write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > {log}\n')
            for f in ("gio", "notify-send"):
                os.chmod(bin_dir / f, 0o755)
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            r = subprocess.run([sys.executable, str(SCRIPTS / "eject-drive.py"), "/dev/sdz1",
                                "/run/media/u/x", "<a href='x'>Evil</a>&"],
                               capture_output=True, text=True, env=env, timeout=30)
            self.assertEqual(r.stdout.strip(), "True")
            body = log.read_text().splitlines()[1]
            self.assertEqual(body, "a href='x'Evil/a can now be safely disconnected.")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest tests/unit/test_list_drives.py tests/unit/test_eject_drive.py -v`
Expected: ERROR — `FileNotFoundError` for `list-drives.py` / `eject-drive.py` and `ModuleNotFoundError: drive_label`.

- [ ] **Step 3: Implement the scripts**

`scripts/drive_label.py`:

```python
"""Drive labels are chosen by whoever formatted the drive, and the eject
notification renders markup, so labels are cleaned before display."""

import re

MAX_LABEL = 64
_UNSAFE = re.compile("[\x00-\x1f\x7f-\x9f\u061c\u200b-\u200f\u202a-\u202e\u2066-\u2069<>&]")


def clean_label(name, fallback="Drive"):
    """Without markup characters, control or bidi marks; at most MAX_LABEL."""
    text = " ".join(_UNSAFE.sub(lambda m: " " if m.group() in "\n\t" else "", str(name or "")).split())
    return text[:MAX_LABEL].strip() or fallback
```

`scripts/list-drives.py`:

```python
#!/usr/bin/env python3
"""List mounted removable drives for the dock as JSON on stdout.

Reads `lsblk -J`. Each drive: dev, name (cleaned label), mountpoint, size,
space ("X free of Y"), fstype, icon. Prints [] on any error.
"""

import json
import os
import subprocess

from drive_label import clean_label

COLUMNS = "NAME,LABEL,MOUNTPOINTS,RM,HOTPLUG,SIZE,TYPE,FSTYPE,MODEL,TRAN"
SKIP = {"/", "/home", "/boot", "[SWAP]", "/var/log", "/var/cache/pacman/pkg"}


def fmt(b):
    return f"{b / (1024 * 1024):.1f} MB" if b < 1024 ** 3 else f"{b / 1024 ** 3:.1f} GB"


def space_for(mp, statvfs):
    try:
        st = statvfs(mp)
    except OSError:
        return ""
    return f"{fmt(st.f_bavail * st.f_frsize)} free of {fmt(st.f_blocks * st.f_frsize)}"


def icon_for(d, rm, fstype):
    if d.get("tran") == "usb" or rm or "usb" in str(d.get("model") or "").lower():
        return "drive-removable-media-usb"
    if fstype in ("iso9660", "udf"):
        return "media-optical"
    if d.get("type") == "disk":
        return "drive-harddisk-usb"
    return "drive-removable-media"


def walk(devs, statvfs, seen, out):
    for d in devs if isinstance(devs, list) else []:
        if not isinstance(d, dict):
            continue
        mps = d.get("mountpoints") or ([d.get("mountpoint")] if d.get("mountpoint") else [])
        rm = bool(d.get("rm") or d.get("hotplug") or d.get("tran") == "usb")
        for mp in mps:
            if not mp or mp in SKIP:
                continue
            if not (rm or mp.startswith("/run/media/") or mp.startswith("/media/")):
                continue
            if mp in seen:
                continue
            seen.add(mp)
            label = d.get("label") or d.get("model") or os.path.basename(mp) or d.get("name")
            fstype = str(d.get("fstype") or "").lower()
            out.append({
                "dev": "/dev/" + str(d.get("name") or ""),
                "name": clean_label(label, "USB Drive"),
                "mountpoint": mp,
                "size": d.get("size", ""),
                "space": space_for(mp, statvfs),
                "fstype": fstype,
                "icon": icon_for(d, rm, fstype),
            })
        if "children" in d:
            walk(d["children"], statvfs, seen, out)
    return out


def drives(data, statvfs=os.statvfs):
    if not isinstance(data, dict):
        return []
    return walk(data.get("blockdevices"), statvfs, set(), [])


def main():
    try:
        res = subprocess.run(["lsblk", "-J", "-o", COLUMNS], capture_output=True, text=True, timeout=10)
        data = json.loads(res.stdout) if res.returncode == 0 else {}
        print(json.dumps(drives(data)))
    except Exception:
        print("[]")


if __name__ == "__main__":
    main()
```

`scripts/eject-drive.py`:

```python
#!/usr/bin/env python3
"""Safely remove a drive: gio, then udisksctl, then umount.

Usage: eject-drive.py DEV MOUNTPOINT NAME
Prints True or False; on success sends a notification naming the drive
(label cleaned: notification bodies render markup).
"""

import subprocess
import sys

from drive_label import clean_label


def unmount(dev, mountpoint, run=subprocess.run):
    attempts = []
    if mountpoint:
        attempts.append(["gio", "mount", "-u", mountpoint])
    if dev:
        attempts.append(["udisksctl", "unmount", "-b", dev])
    if mountpoint:
        attempts.append(["umount", mountpoint])
    for cmd in attempts:
        try:
            if run(cmd, capture_output=True).returncode == 0:
                return True
        except OSError:
            continue
    return False


def main(argv):
    dev = argv[1] if len(argv) > 1 else ""
    mountpoint = argv[2] if len(argv) > 2 else ""
    name = clean_label(argv[3] if len(argv) > 3 else "")
    ok = unmount(dev, mountpoint)
    if ok:
        try:
            subprocess.run(["notify-send", "Device Safely Removed",
                            f"{name} can now be safely disconnected.", "-i", "drive-removable-media"])
        except OSError:
            pass
    print(ok)


if __name__ == "__main__":
    main(sys.argv)
```

Run `chmod +x scripts/list-drives.py scripts/eject-drive.py`.

Note on `clean_label("ab\u202ecd\x07\nef")`: the bidi mark and BEL are removed, the newline becomes a space, so the result is `"abcd ef"`.

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest tests/unit/test_list_drives.py tests/unit/test_eject_drive.py -v`
Expected: all 13 tests pass.

- [ ] **Step 5: Wire the scripts into `Dock.qml` and cap the group name**

In `Dock.qml`, add near `localPathsFromUrls`:

```qml
  // Local filesystem path of a helper in scripts/.
  function scriptPath(name) {
    return decodeURIComponent(Qt.resolvedUrl("scripts/" + name).toString().replace(/^file:\/\//, ""))
  }
```

Replace the `removableDrivesScanner` command (the long `["python3", "-c", "import json, subprocess, os, sys\ntry: ..."]`) with:

```qml
    // scripts/list-drives.py reads lsblk and prints the drives as JSON.
    command: ["python3", root.scriptPath("list-drives.py")]
```

Replace the `ejectProc` command (the long `["python3", "-c", "import subprocess, sys\ndev = ..."` array) with:

```qml
    // scripts/eject-drive.py: gio, then udisksctl, then umount; the label is
    // cleaned before it reaches the notification.
    command: ["python3", root.scriptPath("eject-drive.py"), ejectProc.dev, ejectProc.mountpoint, ejectProc.driveName]
```

In `components/SettingsPanel.qml`, in `TextField { id: nameField` (group name) add after `placeholderText: "Group name"`:

```qml
                      maximumLength: 120   // DockModel.MAX_APP_GROUP_NAME
```

Run: `grep -n 'python3", "-c"' Dock.qml` — Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add scripts/drive_label.py scripts/list-drives.py scripts/eject-drive.py Dock.qml components/SettingsPanel.qml tests/unit/test_list_drives.py tests/unit/test_eject_drive.py
git commit -m "fix(drives): move drive helpers to scripts and clean labels

The eject helper put the drive label, which whoever formatted the drive
chooses, into a notification body that renders markup. Both inline
python programs move from Dock.qml into scripts/ where they are tested;
labels lose markup, control and bidi characters and are capped at 64
characters. A missing gio or udisksctl no longer crashes eject. The
group name field gets the same 120 character cap the config applies."
```

---

### Task 7: Merge into `priard`, verify live, push

**Files:** none new.

- [ ] **Step 1: Full test run in the worktree**

Run (worktree): `node --test tests/unit/*.test.mjs && python3 -m unittest discover -s tests/unit -p 'test_*.py'`
Expected: all pass.

- [ ] **Step 2: Conflict check, then merge**

```bash
cd ~/.config/omarchy/plugins/omadock
git merge-tree --write-tree priard feat/hardening >/dev/null && echo CLEAN
```
Expected: `CLEAN`. If not, resolve in the worktree by rebasing nothing — instead merge `priard`'s conflicting files by hand in a temporary branch, never in the live checkout, and record a ruling. Then:
```bash
git merge --no-ff feat/hardening -m "Merge branch 'feat/hardening' into priard"
node --test tests/unit/*.test.mjs && python3 -m unittest discover -s tests/unit -p 'test_*.py'
omarchy restart shell; sleep 8; bash tests/smoke-test.sh
journalctl --user --since "-30 s" | grep -iE "omadock/" || echo "log clean"
```
Expected: tests pass on `priard` too (its DockModel has the presets additions), `SMOKE TEST PASSED`, `log clean`.

- [ ] **Step 3: Live checks**

```bash
CFG=~/.config/omarchy/omadock.json; S=<scratchpad>; cp $CFG $S/cfg.bak
# 1. a save keeps groups and folders (real arrays inside QML)
python3 -c "import json;d=json.load(open('$CFG'));print(len(d.get('appGroups',[])),len(d.get('pinnedFolders',d.get('folders',[]))))"
omarchy-shell omadock setAlignment "$(python3 -c "import json;print(json.load(open('$CFG')).get('alignment','center'))")"; sleep 1
python3 -c "import json;d=json.load(open('$CFG'));print(len(d.get('appGroups',[])),len(d.get('pinnedFolders',d.get('folders',[]))))"
# 2. a malformed file survives a save
printf '{"broken": ' > $CFG; sleep 1.5; omarchy-shell omadock setAlignment center; sleep 1
cat $CFG; echo
cp $S/cfg.bak $CFG; sleep 1.5
# 3. drives still listed through the new script
omarchy-shell omadock itemGeometry | python3 -c "import json,sys; print([i['id'] for i in json.load(sys.stdin) if i['kind']=='drive'])"
bash tests/smoke-test.sh
```
Expected: the two count lines are identical and non-zero where the user has groups/folders (find the folder key name with `grep -n "conf\.\(pinnedFolders\|folders\)" Dock.qml` first and use it); the malformed file prints `{"broken": ` unchanged; the drive list contains the mounted drive (`/run/media/priard/UPDATE` at planning time, if still mounted); smoke passes; the config is restored (`diff $S/cfg.bak $CFG` empty).

- [ ] **Step 4: Push and prepare the PR**

```bash
git push fork priard
git -C ~/.local/share/omadock-wt/hardening push -u fork feat/hardening
```
Retry once on "remote rejected (failure)". Write the PR body to `<scratchpad>/hardening-pr.md` (summary of the six fixes, who controls each input, the tests and how to run them: `node --test tests/unit/*.test.mjs` and `python3 -m unittest discover -s tests/unit -p 'test_*.py'`). **Ask the user** before running `gh pr create -R thepathless/omadock --head priard:feat/hardening --base main --title "fix: hardening — config bounds, safe stack previews, drive label cleanup" --body-file <scratchpad>/hardening-pr.md`. The user tests by hand: eject a drive (notification text), open a `~/Downloads` stack with an SVG in it.

---

### Task 8: Window previews disclosure (PR #22)

**Files:**
- Modify: `README.md` on `feat/window-previews`

- [ ] **Step 1: Worktree and find the spot**

```bash
cd ~/.config/omarchy/plugins/omadock
git worktree add ~/.local/share/omadock-wt/previews feat/window-previews
cd ~/.local/share/omadock-wt/previews && grep -n -i "tooltip\|preview" README.md | head
```
Expected: lines describing tooltips/features.

- [ ] **Step 2: Add the paragraph** after the feature line that mentions tooltips (or at the end of the features list if none matches):

```markdown
**Window previews.** Hovering an app shows thumbnails of its windows,
including ones minimized to the dock's hidden workspace. They are
captured into GPU memory only while the tooltip is open and are never
written to disk. Turn them off in Settings → Behavior → Window previews.
```

Check the page name: `grep -n '"Window previews"' -B30 components/SettingsPanel.qml | grep 'panel.page ==='` and use the page's label in the sentence.

- [ ] **Step 3: Commit, push, merge**

```bash
git add README.md
git commit -m "docs: say what window previews capture and keep

Previews screen-capture an app's windows, parked ones included. State
that the captures live in GPU memory only while the tooltip is open,
are never saved, and where to turn them off."
git push fork feat/window-previews
cd ~/.config/omarchy/plugins/omadock
git merge-tree --write-tree priard feat/window-previews >/dev/null && echo CLEAN
git merge --no-ff feat/window-previews -m "Merge branch 'feat/window-previews' into priard"
git push fork priard
```
Expected: `CLEAN`, pushes succeed (pushing `feat/window-previews` updates PR #22).

---

## Part B — fork test suite (`priard`, live checkout)

### Task 9: Runner and static checks

**Files:**
- Create: `tests/run-all.sh`, `tests/unit/test_capped_gate.sh`, `tests/static/shaders-in-sync.sh`, `tests/static/manifest.sh`, `tests/static/qmllint.sh`, `tests/static/qmllint_summary.py`, `tests/static/qmllint-baseline.json`, `tests/static/security_grep.py`, `tests/static/security-baseline.json`

**Interfaces:**
- `tests/run-all.sh [--offline|--live|--all]` → exit 0 when every step passes.
- Each static check takes an override so its failure can be demonstrated: `SHADER_DIR`, `MANIFEST`, `GATE_QML`, a root dir argument for `security_grep.py`, and `--update` for both baselines.

- [ ] **Step 1: Write `tests/static/shaders-in-sync.sh`**

```bash
#!/usr/bin/env bash
# Committed .qsb files must be exactly what the .frag sources compile to
# (qsb output is deterministic), so the binaries carry nothing the sources
# do not. SHADER_DIR overrides the directory checked.
set -u
cd "$(dirname "$0")/../.."
QSB=/usr/lib/qt6/bin/qsb
dir=${SHADER_DIR:-shaders}
[ -x "$QSB" ] || { echo "skip: $QSB missing"; exit 0; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
rc=0
for src in "$dir"/*.frag; do
  if ! "$QSB" --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$tmp/out.qsb" "$src" >/dev/null 2>&1; then
    echo "compile failed: $src"; rc=1; continue
  fi
  cmp -s "$tmp/out.qsb" "$src.qsb" || { echo "out of sync: $src.qsb"; rc=1; }
done
exit $rc
```

- [ ] **Step 2: Show it can fail, then pass**

```bash
S=<scratchpad>; rm -rf $S/sh && cp -r shaders $S/sh && printf 'x' >> $S/sh/grain.frag.qsb
SHADER_DIR=$S/sh bash tests/static/shaders-in-sync.sh; echo "exit=$?"
bash tests/static/shaders-in-sync.sh; echo "exit=$?"
```
Expected: first `out of sync: …/grain.frag.qsb` `exit=1`; second `exit=0`.

- [ ] **Step 3: Write `tests/static/manifest.sh`**

```bash
#!/usr/bin/env bash
# manifest.json parses, names the plugin and its entry point, and passes
# Omarchy's own validator. MANIFEST overrides the file (validator skipped).
set -u
cd "$(dirname "$0")/../.."
m=${MANIFEST:-manifest.json}
python3 - "$m" <<'EOF' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("id") == "omadock", "id"
assert d.get("entryPoints", {}).get("overlay") == "DockHost.qml", "entryPoints.overlay"
assert "overlay" in d.get("kinds", []), "kinds"
EOF
[ -n "${MANIFEST:-}" ] || omarchy plugin validate "$PWD"
```

Demonstrate: `printf '{"id":"x"}' > <scratchpad>/m.json; MANIFEST=<scratchpad>/m.json bash tests/static/manifest.sh; echo exit=$?` → AssertionError, `exit=1`; `bash tests/static/manifest.sh; echo exit=$?` → `exit=0`.

- [ ] **Step 4: qmllint baseline**

First inspect the JSON shape: `/usr/lib/qt6/bin/qmllint --json <scratchpad>/l.json DockHost.qml; python3 -c "import json;d=json.load(open('<scratchpad>/l.json'));print(d.keys()); f=d['files'][0]; print(f.keys()); print(f['warnings'][0])"`. Expected keys: `files` → `filename`, `warnings` with `id` (category such as `unqualified`). If the key is not `id`, use the category key printed and record a ruling.

`tests/static/qmllint_summary.py`:

```python
#!/usr/bin/env python3
"""Reduce qmllint --json output to warning counts per file and category,
and compare against a baseline: only new categories or higher counts fail.
'unqualified' and 'import' are noise here (the Omarchy shell's qs.* modules
are not visible to qmllint)."""
import json
import sys

NOISE = {"unqualified", "import"}


def summary(path):
    data = json.load(open(path))
    out = {}
    for f in data.get("files", []):
        name = f.get("filename", "").split("/omadock/")[-1]
        for w in f.get("warnings", []):
            cat = w.get("id") or w.get("type") or "unknown"
            if cat in NOISE:
                continue
            key = f"{name}::{cat}"
            out[key] = out.get(key, 0) + 1
    return dict(sorted(out.items()))


def main(argv):
    if argv[1] == "--compare":
        base, now = json.load(open(argv[2])), json.load(open(argv[3]))
        worse = {k: (base.get(k, 0), v) for k, v in now.items() if v > base.get(k, 0)}
        for k, (b, n) in worse.items():
            print(f"qmllint: {k} {b} -> {n}")
        return 1 if worse else 0
    print(json.dumps(summary(argv[1]), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

`tests/static/qmllint.sh`:

```bash
#!/usr/bin/env bash
# qmllint (Qt 6) on every tracked QML file, compared with a committed
# baseline. --update rewrites the baseline after a reviewed change.
set -u
cd "$(dirname "$0")/../.."
QMLLINT=/usr/lib/qt6/bin/qmllint
[ -x "$QMLLINT" ] || { echo "skip: $QMLLINT missing"; exit 0; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
"$QMLLINT" --json "$tmp/lint.json" $(git ls-files '*.qml') >/dev/null 2>&1
python3 tests/static/qmllint_summary.py "$tmp/lint.json" > "$tmp/now.json" || exit 1
if [ "${1:-}" = "--update" ]; then cp "$tmp/now.json" tests/static/qmllint-baseline.json; exit 0; fi
python3 tests/static/qmllint_summary.py --compare tests/static/qmllint-baseline.json "$tmp/now.json"
```

Run: `bash tests/static/qmllint.sh --update && bash tests/static/qmllint.sh; echo exit=$?` → `exit=0`. Demonstrate failure: `echo '{}' > <scratchpad>/empty.json; cp tests/static/qmllint-baseline.json <scratchpad>/bl.json; cp <scratchpad>/empty.json tests/static/qmllint-baseline.json; bash tests/static/qmllint.sh; echo exit=$?; cp <scratchpad>/bl.json tests/static/qmllint-baseline.json` → lines `qmllint: … 0 -> N`, `exit=1`.

- [ ] **Step 5: Security grep**

`tests/static/security_grep.py`:

```python
#!/usr/bin/env python3
"""Static security audit for the plugin, as the Omarchy marketplace
reviewers check it. Counts risky patterns per rule and file and compares
them with tests/static/security-baseline.json: a new occurrence fails until
it is reviewed and the baseline updated (--update).

Rules:
  text-format     Text/Label block without textFormat: Text.PlainText
  rich-text       RichText / StyledText / MarkdownText anywhere
  dynamic-code    eval( / new Function( / new RegExp( on non-literals
  shell-concat    "sh"/"bash", "-c", "<literal>" followed by + (data spliced
                  into the command instead of passed as $1..)
  hyprctl-eval    every "hyprctl", "eval" call site (Lua is built from
                  strings; each site needs review)
  notify-send     every notify-send call site (bodies render markup)
  python-c        inline python3 -c programs (move them to scripts/)

Usage: security_grep.py [ROOT] [--update]
"""
import json
import pathlib
import re
import sys

RULES = {
    "rich-text": re.compile(r"\b(RichText|StyledText|MarkdownText)\b"),
    "dynamic-code": re.compile(r"\beval\s*\(|new\s+Function\s*\(|new\s+RegExp\s*\(\s*[^\"'/]"),
    "shell-concat": re.compile(r"\"(ba)?sh\",\s*\"-c\",\s*\"(?:[^\"\\]|\\.)*\"\s*\+"),
    "hyprctl-eval": re.compile(r"\"hyprctl\",\s*\"eval\""),
    "notify-send": re.compile(r"notify-send"),
    "python-c": re.compile(r"\"python3\",\s*\"-c\""),
}
TEXT_OPEN = re.compile(r"^\s*(Text|Label)\s*\{")


def text_blocks_without_plaintext(src):
    lines = src.splitlines()
    count = 0
    for i, line in enumerate(lines):
        if not TEXT_OPEN.match(line):
            continue
        depth, body = 0, []
        for l in lines[i:]:
            body.append(l)
            depth += l.count("{") - l.count("}")
            if depth <= 0:
                break
        if "Text.PlainText" not in "\n".join(body):
            count += 1
    return count


def scan(root):
    root = pathlib.Path(root)
    out = {}
    files = [p for p in root.rglob("*") if p.suffix in (".qml", ".js", ".py", ".sh")
             and "tests" not in p.relative_to(root).parts and ".git" not in p.parts
             and ".superpowers" not in p.parts and "docs" not in p.relative_to(root).parts]
    for p in sorted(files):
        rel = str(p.relative_to(root))
        try:
            src = p.read_text(errors="replace")
        except OSError:
            continue
        for rule, rx in RULES.items():
            n = len(rx.findall(src))
            if n:
                out[f"{rule}::{rel}"] = n
        if p.suffix == ".qml":
            n = text_blocks_without_plaintext(src)
            if n:
                out[f"text-format::{rel}"] = n
    return dict(sorted(out.items()))


def main(argv):
    args = [a for a in argv[1:] if a != "--update"]
    root = args[0] if args else pathlib.Path(__file__).resolve().parents[2]
    baseline_path = pathlib.Path(__file__).with_name("security-baseline.json")
    now = scan(root)
    if "--update" in argv:
        baseline_path.write_text(json.dumps(now, indent=1) + "\n")
        return 0
    base = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}
    worse = {k: (base.get(k, 0), v) for k, v in now.items() if v > base.get(k, 0)}
    for k, (b, n) in worse.items():
        print(f"security: {k} {b} -> {n}")
    return 1 if worse else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Run: `python3 tests/static/security_grep.py --update && cat tests/static/security-baseline.json`
Expected: no `rich-text`, `dynamic-code`, `shell-concat`, `python-c` or `text-format` entries (if any appear, inspect each: a real finding gets fixed in a follow-up commit with a ruling; a false positive gets a narrower regex). `hyprctl-eval` and `notify-send` entries list the reviewed call sites.
Demonstrate failure: `mkdir -p <scratchpad>/sg && printf 'Text { text: "x"; textFormat: Text.RichText }\n' > <scratchpad>/sg/A.qml && python3 tests/static/security_grep.py <scratchpad>/sg; echo exit=$?` → `security: rich-text::A.qml 0 -> 1` (and `text-format`), `exit=1`. Then `python3 tests/static/security_grep.py; echo exit=$?` → `exit=0`.

- [ ] **Step 6: Capped read gate test** — `tests/unit/test_capped_gate.sh`

```bash
#!/usr/bin/env bash
# The CappedFileView pre-read gate, extracted from the QML and run as the
# dock runs it: exit 0 + content, 2 = not a readable regular file,
# 3 = over the byte ceiling. GATE_QML overrides the source file.
set -u
cd "$(dirname "$0")/../.."
qml=${GATE_QML:-components/CappedFileView.qml}
gate=$(python3 - "$qml" <<'EOF'
import re, sys
src = open(sys.argv[1]).read()
block = re.search(r"gateScript:\s*\[(.*?)\]\.join\(\"\\n\"\)", src, re.S).group(1)
print("\n".join(re.findall(r"'((?:[^'\\]|\\.)*)'", block)))
EOF
)
[ -n "$gate" ] || { echo "gate script not found in $qml"; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'hello' > "$tmp/small"; head -c 2000 /dev/zero > "$tmp/big"; mkfifo "$tmp/fifo"; mkdir "$tmp/dir"
ln -s /dev/zero "$tmp/zero"
rc=0
check() { # name expected-exit path max [expected-output]
  out=$(timeout 5 sh -c "$gate" gate "$3" "$4"); code=$?
  if [ "$code" != "$2" ] || { [ $# -ge 5 ] && [ "$out" != "$5" ]; }; then
    echo "FAIL $1: exit $code, output '$out'"; rc=1
  fi
}
check small 0 "$tmp/small" 100 hello
check oversize 3 "$tmp/big" 1000
check directory 2 "$tmp/dir" 1000
check fifo 2 "$tmp/fifo" 1000
check dev-zero-symlink 2 "$tmp/zero" 1000
check missing 2 "$tmp/none" 1000
[ $rc = 0 ] && echo "capped gate: 6 cases ok"
exit $rc
```

Demonstrate failure: `sed "s/|| exit 3/|| exit 0/" components/CappedFileView.qml > <scratchpad>/Gate.qml; GATE_QML=<scratchpad>/Gate.qml bash tests/unit/test_capped_gate.sh; echo exit=$?` → `FAIL oversize …`, `exit=1`. Then `bash tests/unit/test_capped_gate.sh` → `capped gate: 6 cases ok`.

- [ ] **Step 7: Runner** — `tests/run-all.sh`

```bash
#!/usr/bin/env bash
# OmaDock tests. --offline (default): unit and static checks, nothing
# outside temp dirs is touched. --live: checks against the running shell
# (backs up and restores omadock.json, no clicks, no keyboard). --all: both.
set -u
cd "$(dirname "$0")/.."
mode=${1:---offline}
fail=0
step() {
  local name=$1; shift
  printf '\n== %s\n' "$name"
  if "$@"; then printf 'ok   %s\n' "$name"; else printf 'FAIL %s\n' "$name"; fail=1; fi
}
offline() {
  step "DockModel (node)" node --test tests/unit/*.test.mjs
  step "scripts (python)" python3 -m unittest discover -s tests/unit -p 'test_*.py'
  step "bench helpers" python3 -m unittest tests/bench/test_bench.py
  step "capped read gate" bash tests/unit/test_capped_gate.sh
  step "shaders in sync" bash tests/static/shaders-in-sync.sh
  step "manifest" bash tests/static/manifest.sh
  step "qmllint baseline" bash tests/static/qmllint.sh
  step "security grep" python3 tests/static/security_grep.py
}
live() {
  step "smoke" bash tests/smoke-test.sh
  step "ipc round-trip" bash tests/live/ipc-roundtrip.sh
  step "config fuzz" bash tests/live/config-fuzz.sh
  step "launch ids" python3 tests/launch-harness.py
}
case $mode in
  --offline) offline ;;
  --live) live ;;
  --all) offline; live ;;
  *) echo "usage: $0 [--offline|--live|--all]"; exit 2 ;;
esac
printf '\n%s\n' "$([ $fail = 0 ] && echo 'ALL PASSED' || echo 'SOME FAILED')"
exit $fail
```

`chmod +x tests/run-all.sh tests/static/*.sh tests/static/*.py tests/unit/test_capped_gate.sh`

Run: `bash tests/run-all.sh; echo exit=$?`
Expected: every offline step `ok`, `ALL PASSED`, `exit=0`.

- [ ] **Step 8: Commit**

```bash
git add tests/run-all.sh tests/unit/test_capped_gate.sh tests/static
git commit -m "test: offline runner with static, shader and security checks

run-all.sh runs unit tests and static checks in seconds without touching
the desktop. Shaders must match their sources byte for byte, the manifest
must validate, qmllint and the security grep compare against reviewed
baselines so only new findings fail, and the CappedFileView read gate is
exercised against FIFOs, directories, /dev/zero and oversized files."
```

---

### Task 10: Characterization tests for DockModel and drop-check

**Files:**
- Create: `tests/unit/dockmodel-core.test.mjs`, `tests/unit/test_drop_check.py`

- [ ] **Step 1: Write `tests/unit/dockmodel-core.test.mjs`**

```js
// Behaviour of DockModel.js that the dock relies on (pinning, grouping,
// app matching, presets). DOCKMODEL overrides the file under test.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const file = process.env.DOCKMODEL || new URL("../../DockModel.js", import.meta.url)
const M = vm.createContext({})
vm.runInContext(readFileSync(file, "utf8"), M)
const plain = (v) => JSON.parse(JSON.stringify(v))

test("stripDesktop", () => {
  assert.equal(M.stripDesktop("firefox.desktop"), "firefox")
  assert.equal(M.stripDesktop({ appId: "x.DESKTOP" }), "x")
  assert.equal(M.stripDesktop(null), "")
})

test("workspaceShort", () => {
  assert.equal(M.workspaceShort(3, "3"), "3")
  assert.equal(M.workspaceShort(-98, "special:magic"), "")
  assert.equal(M.workspaceShort(5, "mail"), "5")
  assert.equal(M.workspaceShort(-1, "7"), "7")
})

test("getCandidates drops vendor tokens", () => {
  const c = plain(M.getCandidates("org.mozilla.firefox"))
  assert.ok(c.includes("firefox"))
  assert.ok(!c.includes("org") && !c.includes("mozilla"))
})

test("isAppMatch", () => {
  assert.equal(M.isAppMatch("firefox", "org.mozilla.firefox"), true)
  assert.equal(M.isAppMatch("Alacritty.desktop", "alacritty"), true)
  assert.equal(M.isAppMatch("zen", "zen-browser"), true)
  assert.equal(M.isAppMatch("vlc", "foot"), false)
  assert.equal(M.isAppMatch("", "foot"), false)
})

test("extractNotificationWebDomain", () => {
  assert.equal(M.extractNotificationWebDomain('<a href="https://web.whatsapp.com/">x</a>', ""), "web.whatsapp.com")
  assert.equal(M.extractNotificationWebDomain("", "Visit https://Music.YouTube.com/watch"), "music.youtube.com")
  assert.equal(M.extractNotificationWebDomain("hello", ""), "")
})

test("serializePinned and parsePinned round-trip", () => {
  const text = M.serializePinned(["a.desktop", "b", "a"])
  assert.deepEqual(JSON.parse(text), { pinned: ["a", "b"] })
  assert.deepEqual(plain(M.parsePinned(text)), ["a", "b"])
})

test("togglePinned", () => {
  assert.deepEqual(plain(M.togglePinned(["a", "b"], "a.desktop")), ["b"])
  assert.deepEqual(plain(M.togglePinned(["a"], "c")), ["a", "c"])
  assert.deepEqual(plain(M.togglePinned(["a"], "")), ["a"])
})

test("reorderPinned", () => {
  assert.deepEqual(plain(M.reorderPinned(["a", "b", "c"], "c", "a")), ["c", "a", "b"])
  assert.deepEqual(plain(M.reorderPinned(["a", "b", "c"], "a", null)), ["b", "c", "a"])
  assert.deepEqual(plain(M.reorderPinned(["a", "b", "c"], "b", "b")), ["a", "b", "c"])
  assert.deepEqual(plain(M.reorderPinned(["a", "b"], "a", "zz")), ["b", "a"])
})

test("moveBefore", () => {
  const list = [1, 2, 3]
  assert.deepEqual(plain(M.moveBefore(list, 0, 3)), [2, 3, 1])
  assert.deepEqual(plain(M.moveBefore(list, 2, 0)), [3, 1, 2])
  assert.equal(M.moveBefore(list, 1, 1), list)
  assert.equal(M.moveBefore(list, 1, 2), list)
  assert.equal(M.moveBefore(list, 5, 0), list)
})

const entries = [{ appId: "a" }, { appId: "b" }]
const groups = [{ id: "g", before: "b", apps: ["a", "c"] }, { id: "h", before: "zz", apps: [] }]

test("pinnedRow places groups before their app, orphans at the end", () => {
  const row = plain(M.pinnedRow(entries, groups))
  assert.deepEqual(row.map((r) => r.kind + ":" + (r.appId || r.id)), ["app:a", "group:g", "app:b", "group:h"])
})

test("rowState turns a row back into pins and anchored groups", () => {
  const st = plain(M.rowState(M.pinnedRow(entries, groups), ["a", "b", "x"]))
  assert.deepEqual(st.pins, ["a", "b", "x"])
  assert.deepEqual(st.groups.map((g) => [g.id, g.before]), [["g", "b"], ["h", ""]])
})

test("ungroupRow puts the group's unshown apps in its place", () => {
  const row = plain(M.ungroupRow(M.pinnedRow(entries, groups), "g"))
  assert.deepEqual(row.map((r) => r.kind + ":" + (r.appId || r.id)), ["app:a", "app:c", "app:b", "group:h"])
})

test("reanchorGroups moves a group past an unpinned anchor", () => {
  const g = [{ id: "g", before: "b" }]
  assert.deepEqual(plain(M.reanchorGroups(g, ["a", "b", "c"], ["a", "c"]))[0].before, "c")
  assert.equal(M.reanchorGroups(g, ["a", "b"], ["a", "b"]), g)
})

test("boundAppGroups defaults and clamps", () => {
  const out = plain(M.boundAppGroups([{ id: "g", cols: 99 }, { id: "h", cols: -5 }, { id: "i" }, { name: "no id" }]))
  assert.deepEqual(out.map((g) => g.cols), [6, 1, 3])
  assert.equal(out[2].name, "Group")
  assert.equal(out[2].icon, "folder")
})

test("boundPinnedFolders whitelists sort and view, caps the count", () => {
  const many = Array.from({ length: 20 }, (_, i) => ({ path: "/f" + i, sort: i ? "bogus" : "name", view: i ? "list" : "grid" }))
  const out = plain(M.boundPinnedFolders(many))
  assert.equal(out.length, 12)
  assert.deepEqual([out[0].sort, out[0].view, out[1].sort, out[1].view], ["name", "grid", "modified", "stack"])
})

test("readCapped counts bytes, not characters", () => {
  assert.equal(M.readCapped("abc", 3), "abc")
  assert.equal(M.readCapped("ąć", 3), "")
  assert.equal(M.readCapped("abcd", 3), "")
})

test("cleanPresetName strips bidi/control characters and caps length", () => {
  assert.equal(M.cleanPresetName("  a\u202eb\u0007  "), "ab")
  assert.equal(M.cleanPresetName("x".repeat(100)).length, 40)
})

test("pickLook keeps look keys only, scalars, capped strings", () => {
  const look = plain(M.pickLook({ bgColor: "x".repeat(100), foo: 1, iconSize: Infinity, shape: { a: 1 } }))
  assert.equal(look.bgColor.length, 64)
  assert.ok(!("foo" in look) && !("shape" in look))
  assert.equal(look.iconSize, 0)
  assert.equal(look.cornerRadius, -1)
})

test("boundPresets validates ids, drops duplicates, caps at six", () => {
  const list = [{ id: "a", name: "A", look: {} }, { id: "a", name: "dup", look: {} }, { id: "bad id", name: "B", look: {} },
    { id: "c", name: "", look: {} }, { id: "d", name: "D", look: [] }]
  for (let i = 0; i < 10; i++) list.push({ id: "p" + i, name: "P" + i, look: {} })
  const out = plain(M.boundPresets(list))
  assert.equal(out.length, 6)
  assert.deepEqual(out.slice(0, 2).map((p) => p.id), ["a", "p0"])
})

test("lookIncludes compares only the preset's keys", () => {
  assert.equal(M.lookIncludes({ grain: true, iconSize: 48 }, { grain: true }), true)
  assert.equal(M.lookIncludes({ grain: false }, { grain: true }), false)
})
```

- [ ] **Step 2: Run, then show the tests catch a change**

Run: `node --test tests/unit/dockmodel-core.test.mjs`
Expected: all pass. If one fails, the test's expectation was read wrong from the code: re-read the function, fix the expectation, ledger a ruling (these are characterization tests of current behaviour).
Then: `sed 's/if (to === from || to === from + 1) return list/if (false) return list/' DockModel.js > <scratchpad>/DM.js; DOCKMODEL=<scratchpad>/DM.js node --test tests/unit/dockmodel-core.test.mjs; echo exit=$?` → `moveBefore` FAILS, `exit=1`.

- [ ] **Step 3: Write `tests/unit/test_drop_check.py`**

```python
import importlib.util
import pathlib
import subprocess
import sys
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "scripts" / "drop-check.py"
spec = importlib.util.spec_from_file_location("drop_check", SCRIPT)
drop_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drop_check)


class Supported(unittest.TestCase):
    def test_exact_and_inherited_types(self):
        self.assertTrue(drop_check.supported("text/plain", ["text/plain"]))
        self.assertTrue(drop_check.supported("text/x-python", ["text/plain"]))

    def test_wildcards(self):
        self.assertTrue(drop_check.supported("image/png", ["image/*"]))
        self.assertFalse(drop_check.supported("text/plain", ["image/*"]))

    def test_unlisted(self):
        self.assertFalse(drop_check.supported("image/png", ["text/plain"]))
        self.assertFalse(drop_check.supported("image/png", []))


class Cli(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True,
                              text=True, timeout=30).stdout.strip()

    def test_too_few_arguments(self):
        self.assertEqual(self.run_cli(), "no")
        self.assertEqual(self.run_cli("foot"), "no")

    def test_unknown_app(self):
        self.assertEqual(self.run_cli("no-such-app-xyz", "/etc/hostname"), "no")


if __name__ == "__main__":
    unittest.main()
```

Run: `python3 -m unittest tests/unit/test_drop_check.py -v` → all pass. Show it can fail: `python3 -c "import sys; sys.argv=['x']" ` is not enough — instead temporarily run `python3 - <<'EOF'` that loads the module, replaces `supported` with `lambda c, t: True`, and runs the `Supported` cases via `unittest` → `test_unlisted` FAILS. (Record the output.)

- [ ] **Step 4: Commit**

```bash
git add tests/unit/dockmodel-core.test.mjs tests/unit/test_drop_check.py
git commit -m "test: characterize DockModel pinning, grouping, matching and presets

Pins the behaviour the dock relies on (pin order, group anchoring,
ungrouping, app id matching, notification domains, preset and look
bounds) and drop-check's MIME matching, so refactors for performance
cannot change it silently."
```

---

### Task 11: `state()` IPC and live tests

**Files:**
- Modify: `DockHost.qml` (IpcHandler)
- Create: `tests/live/ipc-roundtrip.sh`, `tests/live/config-fuzz.sh`

**Interfaces:**
- IPC `state(): string` → `{"visible": bool, "settingsOpen": bool, "settingsPage": str, "activePreset": str, "items": int, "docks": int}`.

- [ ] **Step 1: Confirm RED**: `omarchy-shell omadock state` → `Function not found.`

- [ ] **Step 2: Add `state()`** in `DockHost.qml` after `itemGeometry`:

```qml
    // Read-only summary for the live tests.
    function state(): string {
      var d = host.orderedDocks()
      if (d.length === 0) return "{}"
      return JSON.stringify({
        visible: d[0].dockVisible,
        settingsOpen: d[0].settingsPanelOpen,
        settingsPage: d[0].settingsPanelPage,
        activePreset: d[0].activePresetId || "",
        items: JSON.parse(d[0].itemGeometry()).length,
        docks: d.length
      })
    }
```

Run: `omarchy restart shell; sleep 8; bash tests/smoke-test.sh; omarchy-shell omadock state`
Expected: `SMOKE TEST PASSED` and a JSON object with `"settingsOpen":false`, `"items"` > 0.

- [ ] **Step 3: `tests/live/ipc-roundtrip.sh`**

```bash
#!/usr/bin/env bash
# Live: every IPC function round-trips and leaves the dock mapped with a
# clean log. Backs up omadock.json and restores it on exit. No input.
set -u
cd "$(dirname "$0")/../.."
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
restore() { omarchy-shell omadock closeSettings >/dev/null 2>&1; cp "$bak" "$CFG"; rm -f "$bak"; }
trap restore EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
ipc() { omarchy-shell omadock "$@"; }
st() { ipc state | python3 -c "import json,sys; print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }
fail() { echo "IPC ROUND-TRIP FAILED: $*" >&2; exit 1; }

ipc openSettings; sleep 1
[ "$(st settingsOpen)" = True ] || fail "openSettings"
for page in appearance placement behavior effects size presets folders groups supporters about; do
  ipc openSettingsPage "$page"; sleep 0.4
  [ "$(st settingsPage)" = "$page" ] || fail "openSettingsPage $page"
done
ipc closeSettings; sleep 0.5
[ "$(st settingsOpen)" = False ] || fail "closeSettings"

v=$(st visible)
ipc toggleVisibility; sleep 0.5; ipc toggleVisibility; sleep 0.5
[ "$(st visible)" = "$v" ] || fail "toggleVisibility twice"
ipc reveal; sleep 0.5

[ "$(ipc applyPreset no-such-preset-xyz)" = "not found" ] || fail "applyPreset unknown"
[ "$(ipc applyPreset "$(python3 -c 'print("x" * 10000)')")" = "not found" ] || fail "applyPreset 10k name"

align=$(python3 -c "import json; print(json.load(open('$CFG')).get('alignment', 'center'))")
ipc setAlignment "$align"; sleep 0.5

ipc itemGeometry | python3 -c "import json,sys; assert len(json.load(sys.stdin)) > 0" || fail "itemGeometry empty"
bash tests/smoke-test.sh >/dev/null || fail "smoke test"
if journalctl --user --since "$since" | grep -iE "omadock/.*(error|TypeError|ReferenceError|is not a)"; then
  fail "errors in the log"
fi
echo "IPC ROUND-TRIP PASSED"
```

Run: `bash tests/live/ipc-roundtrip.sh; echo exit=$?` → `IPC ROUND-TRIP PASSED`, `exit=0`; `diff` of the config against a copy taken before the run is empty.

- [ ] **Step 4: `tests/live/config-fuzz.sh`**

```bash
#!/usr/bin/env bash
# Live: malformed omadock.json contents must neither break the dock nor
# be rewritten by it. Backs up the config and restores it on exit.
set -u
cd "$(dirname "$0")/../.."
CFG=$HOME/.config/omarchy/omadock.json
bak=$(mktemp); cp "$CFG" "$bak"
work=$(mktemp -d)
restore() { cp "$bak" "$CFG"; rm -rf "$bak" "$work"; }
trap restore EXIT
since=$(date '+%Y-%m-%d %H:%M:%S')
rc=0

python3 - "$work" <<'EOF'
import json, pathlib, sys
w = pathlib.Path(sys.argv[1])
cases = {
    "empty": "", "garbage": "garbage{", "null": "null", "array": "[]", "string": '"str"',
    "infinity": '{"iconSize": 1e999, "systemBlurSize": 1e999}',
    "wrong-types": '{"iconSize": "big", "pinned": 5, "appGroups": "x", "autohide": "yes"}',
    "array-like": '{"appGroups": {"length": 1000000}, "pinnedFolders": {"length": 1000000}}',
    "bad-sound": '{"urgentSoundName": "../../../etc/passwd", "urgentSound": true}',
    "relative-folder": '{"pinnedFolders": [{"path": "-x"}, {"path": "rel"}]}',
    "oversize": json.dumps({"pad": "x" * (2 * 1024 * 1024)}),
}
for name, text in cases.items():
    (w / name).write_text(text)
EOF

for f in "$work"/*; do
  name=$(basename "$f")
  cp "$f" "$CFG"
  sleep 1.5
  hyprctl layers | grep -q "namespace: omadock" || { echo "FAIL $name: dock layer gone"; rc=1; }
  cmp -s "$f" "$CFG" || { echo "FAIL $name: the dock rewrote the file"; rc=1; }
done

cp "$bak" "$CFG"; sleep 1.5
bash tests/smoke-test.sh >/dev/null || { echo "FAIL: smoke test after fuzz"; rc=1; }
if journalctl --user --since "$since" | grep -iE "omadock/.*(TypeError|ReferenceError|is not a)"; then
  echo "FAIL: runtime errors in the log"; rc=1
fi
[ $rc = 0 ] && echo "CONFIG FUZZ PASSED"
exit $rc
```

Run: `bash tests/live/config-fuzz.sh; echo exit=$?` → `CONFIG FUZZ PASSED`, `exit=0`, config restored (`diff` with a pre-run copy empty). If a case fails, that is a finding: debug with superpowers:systematic-debugging, fix with a test (DockModel helper + unit test), and record it.

- [ ] **Step 5: Launch harness check**

Run: `python3 tests/launch-harness.py; echo exit=$?` — Expected: exit 0. If it fails on this system for reasons unrelated to the dock (an installed app with a broken desktop file), keep it out of `run-all.sh --live`, note why in the README and ledger a ruling.

- [ ] **Step 6: Commit**

```bash
git add DockHost.qml tests/live
git commit -m "test: live IPC round-trip and config fuzz

A read-only state() IPC reports visibility, settings page and active
preset so the live tests can assert outcomes, not just exit codes. The
round-trip drives every IPC function; the fuzz writes eleven malformed
configs and checks the dock stays mapped, logs no runtime errors and
never rewrites the file. Both restore omadock.json on exit."
```

---

### Task 12: Test README, run everything, push

**Files:**
- Create: `tests/README.md`
- Modify (untracked, local only): `CLAUDE.md` "Running and testing"

- [ ] **Step 1: Write `tests/README.md`**

```markdown
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
| `launch-harness.py` | every installed desktop id resolves the way `launch()` builds it |

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
```

- [ ] **Step 2: CLAUDE.md** (local, never committed): in "Running and testing", add the line
`- Tests: \`bash tests/run-all.sh\` (offline) / \`--live\` / \`--all\`; see tests/README.md.`

- [ ] **Step 3: Run everything**

Run: `bash tests/run-all.sh --all; echo exit=$?`
Expected: `ALL PASSED`, `exit=0`, config identical to before.

- [ ] **Step 4: Commit and push**

```bash
git add tests/README.md
git commit -m "docs(tests): how to run the suite and what it covers

Lists each offline and live test with what it checks, what stays manual
and how to update the qmllint and security baselines."
git push fork priard
```
