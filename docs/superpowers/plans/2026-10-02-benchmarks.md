# Repeatable Benchmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command (`tests/bench/bench.py`) that measures the dock's CPU, RAM and VRAM cost in fixed scenarios on the live shell, records hardware and conditions, and compares two runs.

**Architecture:** A stdlib-only Python script. Pure helpers (parsing `/proc`, statistics, coordinate maths, comparison) are unit-tested offline; a thin driver talks to the live desktop through `hyprctl`, `nvidia-smi` and the dock's IPC. The dock gains one read-only IPC function, `itemGeometry()`, so the driver can hover real items.

**Tech Stack:** Python 3.14 stdlib (`unittest`, `statistics`, `threading`, `subprocess`, `xml.etree`), QML (Quickshell 0.3.1), Hyprland 0.56 Lua dispatchers.

**Spec:** `docs/superpowers/specs/2026-10-02-benchmarks-design.md`

## Global Constraints

- Work happens directly on the `priard` branch in the live checkout (this is fork-only tooling). The `itemGeometry()` change is its own commit so it can be cherry-picked upstream later. Never commit `CLAUDE.md`.
- No clicks and no synthetic keyboard input, ever (no `wtype`, no `ydotool`). Pointer moves only: `hyprctl dispatch 'hl.dsp.cursor.move({x=X, y=Y})'` with logical coordinates.
- Every run restores: pointer position, settings closed, the focused workspace, `~/.config/omarchy/shell.json` and the plugin enabled — also on Ctrl-C and on exceptions.
- `--full` restarts the shell; it asks for confirmation unless `--yes`. `--events` switches workspaces; it is opt-in.
- Stdlib only: no pytest, no psutil.
- After any QML change: `omarchy restart shell`, `sleep 8`, `bash tests/smoke-test.sh` must pass, and `journalctl --user --since "-30 s" | grep -iE "omadock/"` must show no new errors.
- Commit messages in English, no AI attribution, one topic per commit with a body explaining why.
- Facts verified on this machine: `nvidia-smi -q -x` lists graphics processes (`quickshell` type `G`) with `used_memory` like `692 MiB` and takes ~0.12 s; `--query-compute-apps` does NOT list quickshell. `quickshell` has no separate render thread (basic render loop): its main thread named `quickshell` does QML and rendering. `CLK_TCK` is 100. `hyprctl layers -j` gives `{monitor: {levels: {"2": [{x, y, w, h, namespace, pid}]}}}`; `hyprctl cursorpos -j` gives `{"x":…, "y":…}`; workspace switch is `hyprctl dispatch 'hl.dsp.focus({ workspace = "N" })'`.

## Review Focus

- `/proc/<pid>/task/<tid>/stat` where the thread name contains spaces or parentheses (`[pango] fontcon`, `QDBusConnection`) — the parser must split on the LAST `)`, not on spaces. Tested in Task 2.
- quickshell restarting (new pid) in the middle of a scenario — sampler must not crash on a vanished `/proc` entry; the run marks the scenario invalid. Tested in Task 2 (`read_proc_sample` returns `None` for a missing pid).
- No item with ≥2 windows, no urgent item, autohide on with the dock hidden — scenarios skip with a reason instead of hovering nothing. Tested in Task 3 (`pick_targets`).
- Ctrl-C during `--full` while the plugin is disabled — `finally` must re-enable it and restore `shell.json`. Verified by hand in Task 4, Step 6.
- Comparing runs from different hardware/versions/config — `compare` warns. Tested in Task 5.

---

## File Structure

```
DockHost.qml                 # + IPC itemGeometry(): string  (delegates to Dock)
Dock.qml                     # + function itemGeometry(): JSON string of item rects
tests/bench/bench.py         # CLI: run / compare; pure helpers + live driver
tests/bench/test_bench.py    # unittest for the pure helpers
tests/bench/README.md        # how to run, scenarios, metrics, caveats
bench/results/               # committed result JSON files
```

`bench.py` stays one file (~450 lines) with sections: pure helpers, sampler, desktop driver, scenarios, CLI. The test file imports it by path.

---

### Task 1: Read-only `itemGeometry()` IPC

**Files:**
- Modify: `Dock.qml` (add a function next to `presetIdByName`, around line 3548)
- Modify: `DockHost.qml` (IpcHandler, after `applyPreset`)

**Interfaces:**
- Produces: IPC `omarchy-shell omadock itemGeometry` → JSON string
  `[{"id": str, "kind": "app"|"group"|"tile"|"folder"|"drive", "x": int, "y": int, "w": int, "h": int, "windows": int, "urgent": bool}]`
  where x/y/w/h are **logical coordinates relative to the dock window** (the bench adds the layer's position from `hyprctl layers -j`). Only visible items with non-zero size are listed.

- [ ] **Step 1: Add the function to `Dock.qml`**

Insert after the `presetIdByName` function:

```qml
  // Read-only snapshot of the dock items' rectangles in window coordinates,
  // for the benchmark and live tests (IPC itemGeometry). Changes nothing.
  function itemGeometry() {
    var out = []
    function add(it, kind, id, windows, urgent) {
      if (!it || !it.visible || it.width <= 0 || it.height <= 0) return
      var p = it.mapToItem(null, 0, 0)
      out.push({ id: String(id || ""), kind: kind,
                 x: Math.round(p.x), y: Math.round(p.y),
                 w: Math.round(it.width), h: Math.round(it.height),
                 windows: windows || 0, urgent: urgent === true })
    }
    var card = root.dockCardComp
    if (!card) return "[]"
    var i, it
    for (i = 0; i < card.pinnedRowRepeater.count; i++) {
      var slot = card.pinnedRowRepeater.itemAt(i)
      it = slot ? slot.item : null
      if (!it) continue
      if (it.groupData !== undefined) add(it, "group", it.groupData.id, 0, false)
      else if (it.appId !== undefined) add(it, "app", it.appId, it.windows, it.urgent)
    }
    var running = card.runningRepeater
    for (i = 0; running && i < running.count; i++) {
      it = running.itemAt(i)
      if (it) add(it, "app", it.appId, it.windows, it.urgent)
    }
    for (i = 0; i < card.minimizedTilesRepeater.count; i++)
      add(card.minimizedTilesRepeater.itemAt(i), "tile", "", 1, false)
    for (i = 0; i < card.foldersRepeater.count; i++) {
      it = card.foldersRepeater.itemAt(i)
      if (it) add(it, "folder", it.folderPath, 0, false)
    }
    for (i = 0; i < card.drivesRepeater.count; i++) {
      it = card.drivesRepeater.itemAt(i)
      if (it) add(it, "drive", it.mountpoint, 0, false)
    }
    return JSON.stringify(out)
  }
```

- [ ] **Step 2: Expose `runningRepeater` from `DockCard.qml` if it is not aliased**

Run: `grep -n "property alias runningRepeater" components/DockCard.qml`
If there is no match, add next to the other aliases (around line 20):

```qml
  property alias runningRepeater: runningRepeater
```

- [ ] **Step 3: Add the IPC function to `DockHost.qml`**

Inside `IpcHandler`, after `applyPreset`:

```qml
    // Read-only: item rectangles of the focused monitor's dock (window
    // coordinates), used by tests/bench/bench.py and the live tests.
    function itemGeometry(): string {
      var d = host.orderedDocks()
      return d.length > 0 ? d[0].itemGeometry() : "[]"
    }
```

- [ ] **Step 4: Restart and verify**

Run:
```bash
omarchy restart shell; sleep 8; bash tests/smoke-test.sh
omarchy-shell omadock itemGeometry | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d)); print(d[:3])"
journalctl --user --since "-30 s" | grep -iE "omadock/" || echo "log clean"
```
Expected: `SMOKE TEST PASSED`, a non-zero count, entries with `kind` `app` and sensible coordinates (y near the bottom of the window, e.g. ~1250–1400 for a 1404-high window), `log clean`.

- [ ] **Step 5: Commit**

```bash
git add Dock.qml DockHost.qml components/DockCard.qml
git commit -m "feat(ipc): read-only itemGeometry for benchmarks and live tests

The dock layer covers most of the screen, so scripts cannot find the
icons from hyprctl. itemGeometry returns each visible item's rectangle in
window coordinates plus its window count and urgency; it changes nothing."
```

---

### Task 2: Pure helpers and the sampler

**Files:**
- Create: `tests/bench/bench.py`
- Create: `tests/bench/test_bench.py`

**Interfaces:**
- Produces (module `bench`):
  - `parse_stat(text: str) -> tuple[str, int]` — `(comm, utime+stime ticks)` from a `/proc/.../stat` line.
  - `read_threads(pid: int) -> dict[str, int] | None` — summed ticks per thread name; `None` if the process is gone.
  - `read_proc_sample(pid: int) -> dict | None` — `{"rss_kb", "pss_kb", "threads", "fds", "ctxsw"}`; `None` if gone.
  - `parse_nvidia_xml(xml_text: str) -> dict[int, int]` — pid → MiB.
  - `cpu_pct(ticks: int, seconds: float, clk_tck: int = 100) -> float`.
  - `summarize(values: list[float]) -> dict` — `{"median", "min", "max"}` (all `None` for an empty list).
  - `class Sampler(pid, hypr_pid)` with `start()`, `stop() -> dict` returning one run's metrics:
    `{"rss_mb", "rss_mb_end", "pss_mb", "vram_mib", "hypr_vram_mib", "cpu_pct", "cpu_threads": {name: pct}, "hypr_cpu_pct", "threads", "fds", "ctxsw_per_s", "valid": bool}`.

- [ ] **Step 1: Write the failing tests**

`tests/bench/test_bench.py`:

```python
import importlib.util
import os
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("bench", HERE / "bench.py")
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class ParseStat(unittest.TestCase):
    def test_plain_name(self):
        line = "123 (quickshell) S 1 2 3 4 5 6 7 8 9 10 250 50 0 0 20 0 18 0"
        self.assertEqual(bench.parse_stat(line), ("quickshell", 300))

    def test_name_with_spaces_and_parens(self):
        line = "124 ([pango] fon(t)) S 1 2 3 4 5 6 7 8 9 10 7 3 0 0 20 0 1 0"
        self.assertEqual(bench.parse_stat(line), ("[pango] fon(t)", 10))


class ReadProc(unittest.TestCase):
    def test_missing_pid_returns_none(self):
        self.assertIsNone(bench.read_proc_sample(999999999))
        self.assertIsNone(bench.read_threads(999999999))

    def test_self_sample_has_fields(self):
        s = bench.read_proc_sample(os.getpid())
        for key in ("rss_kb", "pss_kb", "threads", "fds", "ctxsw"):
            self.assertIn(key, s)
        self.assertGreater(s["rss_kb"], 0)
        self.assertGreaterEqual(s["threads"], 1)


class NvidiaXml(unittest.TestCase):
    def test_parses_graphics_processes(self):
        xml = """<nvidia_smi_log><gpu><processes>
        <process_info><pid>1507</pid><type>G</type><used_memory>757 MiB</used_memory></process_info>
        <process_info><pid>42</pid><type>G</type><used_memory>692 MiB</used_memory></process_info>
        <process_info><pid>7</pid><type>C</type><used_memory>N/A</used_memory></process_info>
        </processes></gpu></nvidia_smi_log>"""
        self.assertEqual(bench.parse_nvidia_xml(xml), {1507: 757, 42: 692})

    def test_garbage_gives_empty(self):
        self.assertEqual(bench.parse_nvidia_xml("not xml"), {})


class Stats(unittest.TestCase):
    def test_cpu_pct(self):
        self.assertAlmostEqual(bench.cpu_pct(50, 10.0, 100), 5.0)
        self.assertEqual(bench.cpu_pct(5, 0.0, 100), 0.0)

    def test_summarize(self):
        self.assertEqual(bench.summarize([3, 1, 2]), {"median": 2, "min": 1, "max": 3})
        self.assertEqual(bench.summarize([]), {"median": None, "min": None, "max": None})


class SamplerSelf(unittest.TestCase):
    def test_sampler_on_own_process(self):
        s = bench.Sampler(os.getpid(), None, interval=0.05, vram_interval=10)
        s.start()
        sum(i * i for i in range(300000))
        m = s.stop()
        self.assertTrue(m["valid"])
        self.assertGreater(m["rss_mb"], 0)
        self.assertGreaterEqual(m["cpu_pct"], 0)
        self.assertIn("cpu_threads", m)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: FAIL / error — `bench.py` does not exist.

- [ ] **Step 3: Implement the helpers and the sampler**

`tests/bench/bench.py` (first part; later tasks append sections below the `# --- driver` marker):

```python
#!/usr/bin/env python3
"""OmaDock performance benchmark (fork tooling, stdlib only).

Measures the quickshell process (Omarchy shell + dock) and Hyprland in
fixed scenarios on the live desktop and writes a JSON report. Pointer
moves only; never clicks or types. See tests/bench/README.md.
"""

import json
import os
import statistics
import subprocess
import threading
import time
import xml.etree.ElementTree as ET

CLK_TCK = os.sysconf("SC_CLK_TCK")


# --- pure helpers -----------------------------------------------------------

def parse_stat(text):
    """(comm, utime+stime) from a /proc stat line; comm may hold spaces/parens."""
    head, _, rest = text.rpartition(")")
    comm = head.split("(", 1)[1]
    fields = rest.split()
    # rest starts at field 3 (state); utime/stime are fields 14/15.
    return comm, int(fields[11]) + int(fields[12])


def read_threads(pid):
    """Ticks summed per thread name, or None when the process is gone."""
    try:
        tids = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return None
    out = {}
    for tid in tids:
        try:
            with open(f"/proc/{pid}/task/{tid}/stat") as f:
                comm, ticks = parse_stat(f.read())
        except (OSError, IndexError, ValueError):
            continue
        out[comm] = out.get(comm, 0) + ticks
    return out


def _status_value(text, key):
    for line in text.splitlines():
        if line.startswith(key + ":"):
            return int(line.split()[1])
    return 0


def read_proc_sample(pid):
    """Memory/thread/fd snapshot, or None when the process is gone."""
    try:
        with open(f"/proc/{pid}/status") as f:
            status = f.read()
        with open(f"/proc/{pid}/smaps_rollup") as f:
            rollup = f.read()
        fds = len(os.listdir(f"/proc/{pid}/fd"))
    except OSError:
        return None
    return {
        "rss_kb": _status_value(status, "VmRSS"),
        "pss_kb": _status_value(rollup, "Pss"),
        "threads": _status_value(status, "Threads"),
        "fds": fds,
        "ctxsw": _status_value(status, "voluntary_ctxt_switches")
        + _status_value(status, "nonvoluntary_ctxt_switches"),
    }


def parse_nvidia_xml(xml_text):
    """pid -> used MiB for every process nvidia-smi reports with a number."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return {}
    out = {}
    for p in root.iter("process_info"):
        mem = (p.findtext("used_memory") or "").split()
        try:
            out[int(p.findtext("pid"))] = int(mem[0])
        except (TypeError, ValueError, IndexError):
            continue
    return out


def read_vram():
    try:
        r = subprocess.run(["nvidia-smi", "-q", "-x"], capture_output=True,
                           text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    return parse_nvidia_xml(r.stdout) if r.returncode == 0 else {}


def cpu_pct(ticks, seconds, clk_tck=CLK_TCK):
    if seconds <= 0:
        return 0.0
    return 100.0 * ticks / clk_tck / seconds


def summarize(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return {"median": None, "min": None, "max": None}
    return {"median": statistics.median(vals), "min": min(vals), "max": max(vals)}


def _ticks(threads):
    return sum(threads.values()) if threads else 0


# --- sampler ----------------------------------------------------------------

class Sampler:
    """Samples a process (and optionally Hyprland) in a background thread."""

    def __init__(self, pid, hypr_pid, interval=0.25, vram_interval=1.0):
        self.pid, self.hypr_pid = pid, hypr_pid
        self.interval, self.vram_interval = interval, vram_interval
        self._stop = threading.Event()
        self._samples, self._vram, self._hvram = [], [], []
        self.valid = True

    def start(self):
        self._t0 = time.monotonic()
        self._threads0 = read_threads(self.pid)
        self._hyp0 = read_threads(self.hypr_pid) if self.hypr_pid else None
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def _loop(self):
        next_vram = 0.0
        while not self._stop.is_set():
            s = read_proc_sample(self.pid)
            if s is None:
                self.valid = False
                return
            self._samples.append(s)
            now = time.monotonic()
            if now >= next_vram:
                v = read_vram()
                self._vram.append(v.get(self.pid))
                if self.hypr_pid:
                    self._hvram.append(v.get(self.hypr_pid))
                next_vram = now + self.vram_interval
            self._stop.wait(self.interval)

    def stop(self):
        self._stop.set()
        self._thread.join()
        secs = time.monotonic() - self._t0
        threads1 = read_threads(self.pid)
        if threads1 is None or self._threads0 is None or not self._samples:
            self.valid = False
        per = {}
        if self.valid:
            for name, t in threads1.items():
                d = t - self._threads0.get(name, 0)
                if d > 0:
                    per[name] = round(cpu_pct(d, secs), 2)
        hyp1 = read_threads(self.hypr_pid) if self.hypr_pid else None
        smp = self._samples
        med = lambda k: statistics.median([x[k] for x in smp]) if smp else None
        return {
            "valid": self.valid,
            "seconds": round(secs, 2),
            "rss_mb": round(med("rss_kb") / 1024, 1) if smp else None,
            "rss_mb_end": round(smp[-1]["rss_kb"] / 1024, 1) if smp else None,
            "pss_mb": round(med("pss_kb") / 1024, 1) if smp else None,
            "vram_mib": summarize(self._vram)["median"],
            "hypr_vram_mib": summarize(self._hvram)["median"],
            "cpu_pct": round(cpu_pct(_ticks(threads1) - _ticks(self._threads0), secs), 2)
            if self.valid else None,
            "cpu_threads": per,
            "hypr_cpu_pct": round(cpu_pct(_ticks(hyp1) - _ticks(self._hyp0), secs), 2)
            if hyp1 is not None and self._hyp0 is not None else None,
            "threads": smp[-1]["threads"] if smp else None,
            "fds": smp[-1]["fds"] if smp else None,
            "ctxsw_per_s": round((smp[-1]["ctxsw"] - smp[0]["ctxsw"]) / secs, 1)
            if len(smp) > 1 and secs > 0 else None,
        }


# --- driver -----------------------------------------------------------------
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: all tests PASS (the sampler test may print nothing; VRAM is `None` for the test process, which is fine).

- [ ] **Step 5: Commit**

```bash
git add tests/bench/bench.py tests/bench/test_bench.py
git commit -m "test(bench): /proc and nvidia-smi sampler for the benchmark

Per-thread CPU, RSS/PSS, fds, context switches and VRAM sampled in a
background thread; helpers are pure and unit-tested so the live driver
stays thin."
```

---

### Task 3: Desktop driver and quick-mode scenarios (S0–S4, S6)

**Files:**
- Modify: `tests/bench/bench.py` (append below `# --- driver`)
- Modify: `tests/bench/test_bench.py` (new test classes)

**Interfaces:**
- Consumes: `Sampler`, `summarize` (Task 2); IPC `itemGeometry` (Task 1).
- Produces:
  - `to_screen(items: list[dict], layer: dict) -> list[dict]` — adds `cx`, `cy` (centre, logical screen coords) using `layer["x"]`, `layer["y"]`.
  - `sweep_path(items: list[dict]) -> list[tuple[int, int]]` — centres left→right then back, without repeating the turning point.
  - `pick_targets(items: list[dict]) -> dict` — `{"multi": item|None, "urgent": item|None}`; `multi` = first `app` with `windows >= 2`.
  - `class Desktop` with `ipc(fn, *args) -> str`, `cursor() -> (x, y)`, `move(x, y)`, `layer() -> dict|None`, `items() -> list[dict]`, `quickshell_pid() -> int|None`, `hyprland_pid() -> int|None`, `active_workspace() -> str`, `focus_workspace(name: str)`, `free_workspace() -> str`.
  - `run_scenarios(desktop, repeat: int, events: bool, log) -> dict` — scenario name → `{"runs": [metrics], "summary": {metric: summarize}, "skipped": str|None}`.
  - `SCENARIOS` constant with durations.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bench/test_bench.py` (before `if __name__`):

```python
class Geometry(unittest.TestCase):
    ITEMS = [
        {"id": "b", "kind": "app", "x": 300, "y": 1300, "w": 60, "h": 60, "windows": 3, "urgent": False},
        {"id": "a", "kind": "app", "x": 200, "y": 1300, "w": 60, "h": 60, "windows": 1, "urgent": True},
        {"id": "f", "kind": "folder", "x": 400, "y": 1300, "w": 60, "h": 60, "windows": 0, "urgent": False},
    ]

    def test_to_screen_adds_centres(self):
        out = bench.to_screen(self.ITEMS, {"x": 10, "y": 36})
        self.assertEqual((out[0]["cx"], out[0]["cy"]), (340, 1366))

    def test_sweep_path_goes_there_and_back(self):
        pts = bench.sweep_path(bench.to_screen(self.ITEMS, {"x": 0, "y": 0}))
        self.assertEqual([p[0] for p in pts], [230, 330, 430, 330])

    def test_sweep_path_empty(self):
        self.assertEqual(bench.sweep_path([]), [])

    def test_pick_targets(self):
        t = bench.pick_targets(self.ITEMS)
        self.assertEqual(t["multi"]["id"], "b")
        self.assertEqual(t["urgent"]["id"], "a")

    def test_pick_targets_none(self):
        t = bench.pick_targets([self.ITEMS[2]])
        self.assertIsNone(t["multi"])
        self.assertIsNone(t["urgent"])


class Workspaces(unittest.TestCase):
    def test_free_workspace_skips_used(self):
        self.assertEqual(bench.first_free_workspace([1, 2, 3, 5]), "4")
        self.assertEqual(bench.first_free_workspace([]), "1")
        self.assertEqual(bench.first_free_workspace([-98, 1]), "2")
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: the new tests ERROR with `AttributeError: module 'bench' has no attribute 'to_screen'` (and `first_free_workspace`).

- [ ] **Step 3: Implement the driver and scenarios**

Append to `tests/bench/bench.py`:

```python
SHELL_PATH = "/usr/share/omarchy/shell"
OUTSIDE_Y = 1250      # enter the dock from above so hover-enter effects fire
DWELL = 0.15          # seconds per item while sweeping

SCENARIOS = [         # (name, seconds, description)
    ("S0", 30, "idle, pointer away from the dock"),
    ("S1", 30, "pointer sweeps across every item and back"),
    ("S2", 15, "tooltip of an app with >= 2 windows (window previews)"),
    ("S3", 15, "settings panel open"),
    ("S4", 30, "idle again after S1-S3 (leak check)"),
    ("S6", 15, "urgent window present, pointer away"),
]
EVENT_SWITCHES = 20


def to_screen(items, layer):
    out = []
    for it in items:
        it = dict(it)
        it["cx"] = layer["x"] + it["x"] + it["w"] // 2
        it["cy"] = layer["y"] + it["y"] + it["h"] // 2
        out.append(it)
    return out


def sweep_path(items):
    pts = [(it["cx"], it["cy"]) for it in sorted(items, key=lambda i: (i["cx"], i["cy"]))]
    return pts + pts[-2:0:-1] if len(pts) > 1 else pts


def pick_targets(items):
    multi = next((i for i in items if i["kind"] == "app" and i.get("windows", 0) >= 2), None)
    urgent = next((i for i in items if i.get("urgent")), None)
    return {"multi": multi, "urgent": urgent}


def first_free_workspace(used_ids):
    used = {int(i) for i in used_ids}
    n = 1
    while n in used:
        n += 1
    return str(n)


def _run(cmd, timeout=10):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout


class Desktop:
    """Everything that touches the live desktop. Pointer moves only."""

    def ipc(self, fn, *args):
        return _run(["qs", "-p", SHELL_PATH, "ipc", "call", "omadock", fn, *args]).strip()

    def hypr_json(self, *args):
        return json.loads(_run(["hyprctl", *args, "-j"]) or "null")

    def cursor(self):
        c = self.hypr_json("cursorpos")
        return int(c["x"]), int(c["y"])

    def move(self, x, y):
        _run(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{x={int(x)}, y={int(y)}}})"])

    def layer(self):
        for mon in (self.hypr_json("layers") or {}).values():
            for layers in mon.get("levels", {}).values():
                for l in layers:
                    if l.get("namespace") == "omadock":
                        return l
        return None

    def items(self):
        layer = self.layer()
        if layer is None:
            return []
        try:
            raw = json.loads(self.ipc("itemGeometry") or "[]")
        except json.JSONDecodeError:
            return []
        return to_screen(raw, layer)

    def quickshell_pid(self):
        out = _run(["pgrep", "-x", "quickshell"]).split()
        return int(out[0]) if out else None

    def hyprland_pid(self):
        out = _run(["pgrep", "-x", "Hyprland"]).split()
        return int(out[0]) if out else None

    def active_workspace(self):
        return str(self.hypr_json("activeworkspace")["name"])

    def focus_workspace(self, name):
        safe = str(name).replace("\\", "\\\\").replace('"', '\\"')
        _run(["hyprctl", "dispatch", f'hl.dsp.focus({{ workspace = "{safe}" }})'])

    def free_workspace(self):
        return first_free_workspace([w["id"] for w in self.hypr_json("workspaces")])


def measure(desktop, seconds, action=None):
    """One run: sample for `seconds` while `action(deadline)` drives the desktop."""
    s = Sampler(desktop.quickshell_pid(), desktop.hyprland_pid())
    s.start()
    deadline = time.monotonic() + seconds
    if action:
        action(deadline)
    remaining = deadline - time.monotonic()
    if remaining > 0:
        time.sleep(remaining)
    return s.stop()


def run_scenarios(desktop, repeat, events, log):
    items = desktop.items()
    targets = pick_targets(items)
    away = (desktop.layer() or {"x": 0, "w": 400})
    away_xy = (away["x"] + away["w"] // 2, OUTSIDE_Y // 2)
    results = {}

    def park():
        desktop.move(*away_xy)

    def sweep(deadline):
        path = sweep_path(items)
        if not path:
            return
        desktop.move(path[0][0], OUTSIDE_Y)
        while time.monotonic() < deadline:
            for x, y in path:
                if time.monotonic() >= deadline:
                    break
                desktop.move(x, y)
                time.sleep(DWELL)

    def hover_multi(deadline):
        t = targets["multi"]
        desktop.move(t["cx"], OUTSIDE_Y)
        time.sleep(0.2)
        desktop.move(t["cx"], t["cy"])

    def settings(deadline):
        desktop.ipc("openSettings")

    plan = [
        ("S0", None, None),
        ("S1", sweep, None if items else "no dock items found"),
        ("S2", hover_multi, None if targets["multi"] else "no app with >= 2 windows"),
        ("S3", settings, None),
        ("S4", None, None),
        ("S6", None, None if targets["urgent"] else "no urgent window"),
    ]
    durations = {name: secs for name, secs, _ in SCENARIOS}
    for name, action, skip in plan:
        if skip:
            log(f"{name}: skipped ({skip})")
            results[name] = {"runs": [], "summary": {}, "skipped": skip}
            continue
        runs = []
        for i in range(repeat):
            park()
            time.sleep(2)
            log(f"{name} run {i + 1}/{repeat} ({durations[name]} s)")
            runs.append(measure(desktop, durations[name], action))
            if name == "S3":
                desktop.ipc("closeSettings")
            park()
        results[name] = {"runs": runs, "summary": summarize_runs(runs), "skipped": None}
    if events:
        results["S5"] = run_events(desktop, repeat, log)
    return results


NUMERIC = ["rss_mb", "rss_mb_end", "pss_mb", "vram_mib", "hypr_vram_mib", "cpu_pct",
           "hypr_cpu_pct", "threads", "fds", "ctxsw_per_s"]


def summarize_runs(runs):
    good = [r for r in runs if r.get("valid")]
    return {k: summarize([r.get(k) for r in good]) for k in NUMERIC}


def run_events(desktop, repeat, log):
    home = desktop.active_workspace()
    other = desktop.free_workspace()
    runs = []
    try:
        for i in range(repeat):
            log(f"S5 run {i + 1}/{repeat} ({EVENT_SWITCHES} switches {home} <-> {other})")

            def flip(deadline):
                for n in range(EVENT_SWITCHES):
                    desktop.focus_workspace(other if n % 2 == 0 else home)
                    time.sleep(0.5)
                desktop.focus_workspace(home)

            runs.append(measure(desktop, EVENT_SWITCHES * 0.5 + 2, flip))
    finally:
        desktop.focus_workspace(home)
    return {"runs": runs, "summary": summarize_runs(runs), "skipped": None}
```

- [ ] **Step 4: Run the unit tests**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: all PASS.

- [ ] **Step 5: Live check of the driver primitives (no scenario yet)**

Run:
```bash
python3 - <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bench", "tests/bench/bench.py")
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)
d = b.Desktop()
print("pid", d.quickshell_pid(), "hypr", d.hyprland_pid(), "ws", d.active_workspace(), "free", d.free_workspace())
items = d.items(); print(len(items), items[:2]); print(b.pick_targets(items))
x, y = d.cursor(); d.move(x + 1, y); d.move(x, y); print("cursor ok", d.cursor())
EOF
```
Expected: pids printed, items with `cx`/`cy` near the bottom of the screen (cy ≈ 1300–1440), cursor back at its original position.

- [ ] **Step 6: Commit**

```bash
git add tests/bench/bench.py tests/bench/test_bench.py
git commit -m "test(bench): pointer-driven scenarios for the live dock

Idle, hover sweep, window-preview tooltip, settings, leak check, urgent
and opt-in workspace switching, each sampled with the per-thread sampler.
Targets come from itemGeometry; scenarios skip with a reason when the
desktop lacks what they need."
```

---

### Task 4: CLI `run`, conditions, safety and `--full`

**Files:**
- Modify: `tests/bench/bench.py` (append CLI section)
- Modify: `tests/bench/test_bench.py`

**Interfaces:**
- Consumes: `Desktop`, `run_scenarios`, `measure`, `summarize_runs` (Task 3).
- Produces:
  - `conditions(desktop) -> dict` — hardware, versions, git commit/dirty, config sha256, counts, monitor, quickshell uptime, load average.
  - `result_path(out_dir: str, host: str, when: time.struct_time) -> str` — `"<out_dir>/<YYYY-MM-DD-HHMM>-<host>.json"`.
  - `run_full(desktop, log) -> dict` — `{"disabled": metrics, "enabled": metrics, "dock_cost": {metric: enabled - disabled}}`.
  - `main(argv) -> int` with subcommands `run` and `compare` (compare added in Task 5).
  - Report JSON: `{"schema": 1, "started": iso8601, "args": {...}, "conditions": {...}, "scenarios": {...}, "full": {...}|null}`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bench/test_bench.py`:

```python
class Report(unittest.TestCase):
    def test_result_path(self):
        import time as _t
        when = _t.strptime("2026-10-02 14:05", "%Y-%m-%d %H:%M")
        self.assertEqual(bench.result_path("bench/results", "tower", when),
                         "bench/results/2026-10-02-1405-tower.json")

    def test_dock_cost(self):
        cost = bench.dock_cost({"vram_mib": 496, "rss_mb": 858.0, "cpu_pct": None},
                               {"vram_mib": 690, "rss_mb": 896.5, "cpu_pct": 1.2})
        self.assertEqual(cost["vram_mib"], 194)
        self.assertAlmostEqual(cost["rss_mb"], 38.5)
        self.assertIsNone(cost["cpu_pct"])
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: ERROR `AttributeError: ... 'result_path'`.

- [ ] **Step 3: Implement the CLI**

Append to `tests/bench/bench.py`:

```python
# --- report / CLI -----------------------------------------------------------

import argparse
import hashlib
import shutil
import socket
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.expanduser("~/.config/omarchy/omadock.json")
SHELL_JSON = os.path.expanduser("~/.config/omarchy/shell.json")
SETTLE = 20          # seconds after a shell restart before measuring


def result_path(out_dir, host, when):
    return os.path.join(out_dir, time.strftime("%Y-%m-%d-%H%M", when) + f"-{host}.json")


def dock_cost(disabled, enabled):
    out = {}
    for k in NUMERIC:
        a, b = disabled.get(k), enabled.get(k)
        out[k] = round(b - a, 2) if a is not None and b is not None else None
    return out


def _sh(cmd):
    try:
        return _run(cmd).strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def conditions(desktop):
    cpu = next((l.split(":", 1)[1].strip() for l in open("/proc/cpuinfo")
                if l.startswith("model name")), "")
    mem_kb = _status_value(open("/proc/meminfo").read(), "MemTotal")
    pid = desktop.quickshell_pid()
    try:
        cfg = hashlib.sha256(open(CONFIG, "rb").read()).hexdigest()[:16]
    except OSError:
        cfg = None
    monitors = desktop.hypr_json("monitors") or []
    items = desktop.items()
    started = None
    if pid:
        boot = time.time() - float(open("/proc/uptime").read().split()[0])
        start_ticks = int(open(f"/proc/{pid}/stat").read().rpartition(")")[2].split()[19])
        started = round(time.time() - (boot + start_ticks / CLK_TCK))
    return {
        "host": socket.gethostname(),
        "cpu": cpu,
        "cores": os.cpu_count(),
        "ram_gb": round(mem_kb / 1024 / 1024, 1),
        "gpu": _sh(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"]),
        "kernel": os.uname().release,
        "packages": _sh(["pacman", "-Q", "omarchy", "quickshell", "hyprland", "qt6-base"]).splitlines(),
        "dock_commit": _sh(["git", "-C", REPO, "rev-parse", "--short", "HEAD"]),
        "dock_dirty": bool(_sh(["git", "-C", REPO, "status", "--porcelain", "--untracked-files=no"])),
        "config_sha256": cfg,
        "items": len(items),
        "items_by_kind": {k: sum(1 for i in items if i["kind"] == k) for k in {i["kind"] for i in items}},
        "windows": len(desktop.hypr_json("clients") or []),
        "monitors": [f'{m["name"]} {m["width"]}x{m["height"]}@{m["refreshRate"]:.0f} scale {m["scale"]}'
                     for m in monitors],
        "dock_layer": desktop.layer(),
        "quickshell_uptime_s": started,
        "loadavg": os.getloadavg(),
    }


def wait_quiet(log, limit=1.5, timeout=30):
    end = time.monotonic() + timeout
    while os.getloadavg()[0] > limit and time.monotonic() < end:
        time.sleep(2)
    load = os.getloadavg()[0]
    if load > limit:
        log(f"warning: load average {load:.2f} stays above {limit}; results may be noisy")
    return load


def restart_shell(desktop, log):
    _run(["omarchy", "restart", "shell"], timeout=60)
    for _ in range(60):
        if desktop.quickshell_pid():
            break
        time.sleep(1)
    log(f"shell restarted, settling {SETTLE} s")
    time.sleep(SETTLE)


def run_full(desktop, log):
    backup = open(SHELL_JSON, "rb").read()
    result = {}
    try:
        log("full: disabling omadock")
        _run(["omarchy", "plugin", "disable", "omadock"], timeout=30)
        restart_shell(desktop, log)
        result["disabled"] = measure(desktop, 30)
    finally:
        log("full: enabling omadock")
        _run(["omarchy", "plugin", "enable", "omadock"], timeout=30)
        with open(SHELL_JSON, "wb") as f:
            f.write(backup)
        restart_shell(desktop, log)
    result["enabled"] = measure(desktop, 30)
    result["dock_cost"] = dock_cost(result["disabled"], result["enabled"])
    return result


def print_summary(report):
    print(f'\n## Benchmark {report["started"]} ({report["conditions"]["dock_commit"]}'
          f'{" dirty" if report["conditions"]["dock_dirty"] else ""})\n')
    print("| scenario | cpu % | hypr cpu % | rss MB | vram MiB | fds | ctxsw/s |")
    print("|---|---|---|---|---|---|---|")
    for name, sc in report["scenarios"].items():
        if sc["skipped"]:
            print(f"| {name} | skipped: {sc['skipped']} | | | | | |")
            continue
        s = sc["summary"]
        cell = lambda k: "–" if s[k]["median"] is None else f'{s[k]["median"]:g}'
        print(f"| {name} | {cell('cpu_pct')} | {cell('hypr_cpu_pct')} | {cell('rss_mb')} | "
              f"{cell('vram_mib')} | {cell('fds')} | {cell('ctxsw_per_s')} |")
    if report.get("full"):
        c = report["full"]["dock_cost"]
        print(f'\nDock cost (enabled - disabled): vram {c["vram_mib"]} MiB, '
              f'rss {c["rss_mb"]} MB, cpu {c["cpu_pct"]} %')


def cmd_run(args):
    log = lambda m: print(f"[bench] {m}", file=sys.stderr, flush=True)
    desktop = Desktop()
    if not desktop.quickshell_pid() or desktop.layer() is None:
        log("quickshell or the omadock layer is missing; run tests/smoke-test.sh")
        return 1
    if args.full and not args.yes:
        answer = input("--full restarts the shell 2x (bar and dock vanish briefly). Continue? [y/N] ")
        if answer.strip().lower() != "y":
            return 1
    cursor = desktop.cursor()
    report = {"schema": 1, "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
              "args": vars(args) | {"func": None}, "full": None}
    try:
        report["load_before"] = wait_quiet(log)
        report["conditions"] = conditions(desktop)
        desktop.ipc("reveal")
        report["scenarios"] = run_scenarios(desktop, args.repeat, args.events, log)
        if args.full:
            report["full"] = run_full(desktop, log)
    finally:
        desktop.ipc("closeSettings")
        desktop.move(*cursor)
    os.makedirs(args.out, exist_ok=True)
    path = result_path(args.out, report["conditions"]["host"], time.localtime())
    with open(path, "w") as f:
        json.dump(report, f, indent=1)
    print_summary(report)
    print(f"\nSaved {os.path.relpath(path, REPO)}")
    smoke = subprocess.run(["bash", os.path.join(REPO, "tests/smoke-test.sh")])
    return smoke.returncode


def main(argv=None):
    p = argparse.ArgumentParser(prog="bench.py", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="measure the live dock")
    r.add_argument("--full", action="store_true", help="also measure plugin disabled vs enabled (restarts the shell)")
    r.add_argument("--events", action="store_true", help="also switch workspaces (S5)")
    r.add_argument("--repeat", type=int, default=3)
    r.add_argument("--yes", action="store_true", help="do not ask before restarting the shell")
    r.add_argument("--out", default=os.path.join(REPO, "bench", "results"))
    r.set_defaults(func=cmd_run)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
```

Note: `_status_value` reads `MemTotal: 65000000 kB` lines the same way as `/proc/<pid>/status`, so it is reused for `/proc/meminfo`.

- [ ] **Step 4: Run unit tests**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: all PASS.

- [ ] **Step 5: Short live run**

Run: `python3 tests/bench/bench.py run --repeat 1 --out /tmp/claude-bench`
(Use the session scratchpad directory instead of `/tmp/claude-bench` when running as an agent.)
Expected: progress lines for S0–S4 (S2/S6 may say skipped with a reason), a Markdown table, `Saved …`, then `SMOKE TEST PASSED`. Pointer ends where it started; settings closed.

- [ ] **Step 6: Interrupt safety check for `--full`**

Run `python3 tests/bench/bench.py run --full --yes --repeat 1 --out <scratch>` and press Ctrl-C while the log says `full: disabling omadock` has happened and before `enabling`. (This step is done by the user, who presses Ctrl-C; the agent asks them to.)
Expected: the log still prints `full: enabling omadock`, the shell restarts, `omarchy plugin list --json` shows omadock enabled, `diff` against a pre-run copy of `shell.json` is empty, `bash tests/smoke-test.sh` passes.

- [ ] **Step 7: Commit**

```bash
git add tests/bench/bench.py tests/bench/test_bench.py
git commit -m "test(bench): run command with conditions, report and --full

Records hardware, versions, dock commit and config hash with every run,
restores pointer and settings, and --full measures the shell with the
plugin disabled and enabled to get the dock's absolute cost."
```

---

### Task 5: `compare`

**Files:**
- Modify: `tests/bench/bench.py`
- Modify: `tests/bench/test_bench.py`

**Interfaces:**
- Consumes: report JSON from Task 4.
- Produces:
  - `compare_reports(a: dict, b: dict) -> tuple[list[dict], list[str]]` — rows `{"scenario", "metric", "a", "b", "diff", "pct", "noise": bool}` and warnings.
  - CLI `bench.py compare A.json B.json` printing a Markdown table and warnings.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bench/test_bench.py`:

```python
def _report(cpu_runs, vram, commit="abc", pkgs=("quickshell 0.3.1-1",)):
    runs = [{"valid": True, "cpu_pct": c, "vram_mib": vram} for c in cpu_runs]
    return {"conditions": {"cpu": "X", "gpu": "G", "packages": list(pkgs),
                           "config_sha256": "h", "monitors": ["DP-1"], "dock_commit": commit},
            "scenarios": {"S0": {"runs": runs, "summary": bench.summarize_runs(runs), "skipped": None},
                          "S2": {"runs": [], "summary": {}, "skipped": "no app"}}}


class Compare(unittest.TestCase):
    def test_rows_and_noise(self):
        a = _report([1.0, 1.2, 1.1], 690)
        b = _report([0.5, 0.6, 0.55], 520, commit="def")
        rows, warnings = bench.compare_reports(a, b)
        cpu = next(r for r in rows if r["scenario"] == "S0" and r["metric"] == "cpu_pct")
        self.assertAlmostEqual(cpu["diff"], -0.55)
        self.assertFalse(cpu["noise"])
        self.assertEqual(warnings, [])
        self.assertFalse(any(r["scenario"] == "S2" for r in rows))

    def test_small_diff_is_noise(self):
        rows, _ = bench.compare_reports(_report([1.0, 1.4], 690), _report([1.1, 1.3], 690))
        cpu = next(r for r in rows if r["metric"] == "cpu_pct")
        self.assertTrue(cpu["noise"])

    def test_warns_on_different_conditions(self):
        _, warnings = bench.compare_reports(_report([1], 1), _report([1], 1, pkgs=("quickshell 0.4.0-1",)))
        self.assertTrue(any("packages" in w for w in warnings))
```

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: ERROR `AttributeError: ... 'compare_reports'`.

- [ ] **Step 3: Implement**

Insert into `tests/bench/bench.py` above `def main`:

```python
COMPARED_CONDITIONS = ["cpu", "gpu", "packages", "config_sha256", "monitors"]


def compare_reports(a, b):
    warnings = [f"conditions differ: {k}"
                for k in COMPARED_CONDITIONS
                if a["conditions"].get(k) != b["conditions"].get(k)]
    rows = []
    for name, sa in a["scenarios"].items():
        sb = b["scenarios"].get(name)
        if not sb or sa["skipped"] or sb["skipped"]:
            continue
        for k in NUMERIC:
            ma, mb = sa["summary"].get(k, {}), sb["summary"].get(k, {})
            va, vb = ma.get("median"), mb.get("median")
            if va is None or vb is None:
                continue
            diff = vb - va
            spread = max(ma["max"] - ma["min"], mb["max"] - mb["min"])
            rows.append({"scenario": name, "metric": k, "a": va, "b": vb,
                         "diff": round(diff, 3),
                         "pct": round(100 * diff / va, 1) if va else None,
                         "noise": abs(diff) <= spread})
    return rows, warnings


def cmd_compare(args):
    a, b = (json.load(open(p)) for p in (args.a, args.b))
    rows, warnings = compare_reports(a, b)
    for w in warnings:
        print(f"warning: {w}")
    print(f'\n## {a["conditions"]["dock_commit"]} → {b["conditions"]["dock_commit"]}\n')
    print("| scenario | metric | A | B | Δ | Δ % | |")
    print("|---|---|---|---|---|---|---|")
    for r in rows:
        pct = "–" if r["pct"] is None else f'{r["pct"]:+g} %'
        print(f'| {r["scenario"]} | {r["metric"]} | {r["a"]:g} | {r["b"]:g} | '
              f'{r["diff"]:+g} | {pct} | {"noise" if r["noise"] else ""} |')
    return 0
```

In `main`, register the subcommand (before `args = p.parse_args(argv)`):

```python
    c = sub.add_parser("compare", help="compare two result files")
    c.add_argument("a")
    c.add_argument("b")
    c.set_defaults(func=cmd_compare)
```

- [ ] **Step 4: Run tests**

Run: `python3 -m unittest tests/bench/test_bench.py -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add tests/bench/bench.py tests/bench/test_bench.py
git commit -m "test(bench): compare two benchmark runs

Prints per-scenario medians, absolute and relative change, marks changes
within the measured spread as noise and warns when hardware, versions or
config differ between the runs."
```

---

### Task 6: README and the baseline run

**Files:**
- Create: `tests/bench/README.md`
- Create: `bench/results/<date>-<host>.json` (generated)

- [ ] **Step 1: Write `tests/bench/README.md`**

```markdown
# OmaDock benchmark

Measures what the dock costs in CPU, RAM and VRAM on the live desktop, in
fixed scenarios, and compares runs. Fork tooling, Python stdlib only.

## Run

    python3 tests/bench/bench.py run                 # quick: S0-S4, S6, ~4 min
    python3 tests/bench/bench.py run --events        # + S5 workspace switching
    python3 tests/bench/bench.py run --full          # + dock on/off (restarts the shell 2x)
    python3 tests/bench/bench.py compare A.json B.json

Results land in `bench/results/<date>-<host>.json`; commit the ones worth
keeping (baselines, before/after of an optimisation).

## What it does to your desktop

- Moves the pointer (never clicks or types) and puts it back.
- Opens and closes the settings panel through IPC.
- `--events` switches to an empty workspace and back 20 times per run.
- `--full` disables the plugin, restarts the shell, measures, re-enables
  it, restores `shell.json` and restarts again. Ctrl-C is safe: the plugin
  is always re-enabled.
- Do not use the computer while it runs; input changes the numbers.

## Scenarios

| # | what | seconds |
|---|---|---|
| S0 | idle, pointer away from the dock | 30 |
| S1 | pointer sweeps across every item and back | 30 |
| S2 | tooltip of an app with >= 2 windows (window previews) | 15 |
| S3 | settings panel open | 15 |
| S4 | idle after S1-S3; compare with S0 for leaks | 30 |
| S5 | `--events`: 20 workspace switches | ~12 |
| S6 | an urgent window exists (skipped if none) | 15 |

Each runs `--repeat` times (default 3); the report keeps every run plus
median/min/max.

## Metrics

All for the `quickshell` process, which also hosts the Omarchy bar,
background and notifications. Only `--full` isolates the dock itself.

- `cpu_pct`: CPU over the window, 100 = one core. `cpu_threads` splits it
  by thread name; `quickshell` (main thread) does QML and rendering.
- `hypr_cpu_pct`: Hyprland's CPU in the same window. It pays for
  compositing and blurring the dock surface.
- `rss_mb`, `pss_mb`: resident / proportional memory (median of samples);
  `rss_mb_end` is the last sample.
- `vram_mib`, `hypr_vram_mib`: from `nvidia-smi -q -x` (NVIDIA only).
- `fds`, `threads`: should not grow between S0 and S4.
- `ctxsw_per_s`: context switches per second, a wake-up proxy; at idle it
  should be low and flat.

## Conditions recorded with each run

CPU, cores, RAM, GPU and driver, kernel, `omarchy`/`quickshell`/
`hyprland`/`qt6-base` versions, dock commit and dirty flag, sha256 of
`omadock.json`, item count by kind, window count, monitors, dock layer
geometry, quickshell uptime, load average. `compare` warns when the
hardware, versions, config or monitors differ.

## Caveats

- Numbers from different machines or configs are not comparable.
- Freshly restarted shells use less RAM than ones that ran for hours;
  check `quickshell_uptime_s` before comparing RSS.
- VRAM is reported by the driver and is freed lazily; compare medians.

## Unit tests

    python3 -m unittest tests/bench/test_bench.py -v
```

- [ ] **Step 2: Baseline run**

Ask the user to leave the computer alone for ~8 minutes, then run:
`python3 tests/bench/bench.py run --full --events --yes`
Expected: table printed, `Saved bench/results/…json`, smoke test passes.

- [ ] **Step 3: Commit**

```bash
git add tests/bench/README.md bench/results/*.json
git commit -m "test(bench): README and baseline benchmark run

Documents how to run the benchmark, what it does to the desktop and what
each number means, and stores the baseline the performance work is
measured against."
```

- [ ] **Step 4: Push**

Run: `git push fork priard` (retry once on "remote rejected (failure)").
