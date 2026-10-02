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
    for _ in range(3):          # a hidden dock reports no visible items
        if items:
            break
        desktop.ipc("reveal")
        time.sleep(1)
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
