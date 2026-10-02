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
