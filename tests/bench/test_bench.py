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

if __name__ == "__main__":
    unittest.main()
