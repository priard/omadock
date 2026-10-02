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
