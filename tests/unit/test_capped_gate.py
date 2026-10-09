"""The CappedFileView pre-read gate, taken from the QML and run the way the
dock runs it (sh -c GATE name PATH MAX): exit 0 with the content, 2 for
anything that is not a readable regular file, 3 for a file over the cap.
GATE_QML overrides the QML file (to check that the test can fail)."""
import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
QML = pathlib.Path(os.environ.get("GATE_QML", ROOT / "components" / "CappedFileView.qml"))


def gate_script():
    src = QML.read_text()
    block = re.search(r'gateScript:\s*\[(.*?)\]\.join\("\\n"\)', src, re.S).group(1)
    return "\n".join(re.findall(r"'((?:[^'\\]|\\.)*)'", block))


GATE = gate_script()


class Gate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gate = GATE

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)

    def run_gate(self, path, cap):
        return subprocess.run(["sh", "-c", self.gate, "gate", str(path), str(cap)],
                              capture_output=True, text=True, timeout=10)

    def test_small_regular_file_is_read(self):
        (self.dir / "small").write_text("hello")
        r = self.run_gate(self.dir / "small", 100)
        self.assertEqual((r.returncode, r.stdout), (0, "hello"))

    def test_oversize_file_is_refused(self):
        (self.dir / "big").write_bytes(b"\0" * 2000)
        self.assertEqual(self.run_gate(self.dir / "big", 1000).returncode, 3)

    def test_directory_fifo_device_and_missing_are_refused(self):
        (self.dir / "dir").mkdir()
        os.mkfifo(self.dir / "fifo")
        (self.dir / "zero").symlink_to("/dev/zero")
        for name in ("dir", "fifo", "zero", "missing"):
            with self.subTest(name=name):
                self.assertEqual(self.run_gate(self.dir / name, 1000).returncode, 2)


class ReadRace(unittest.TestCase):
    """A watched file replaced mid-read must never be emitted as a prefix of
    its new content.

    The dock writes omadock.json the way FileView does with atomicWrites: a
    temporary file, then one rename - and the file grows when a preset is
    saved. A gate that reads the size, then reads exactly that many bytes, has
    a window between the two steps: with a rename landing inside it, it emitted
    the first len(old) bytes of the NEW file, a truncated JSON document. The
    dock logged `Failed parsing omadock.json` and applied defaults, which is
    how the preset list it holds in memory emptied after a save.

    Nothing is stubbed out: only `head` is slowed, so the real rename lands
    inside the read window the way it does on a busy desktop.
    """

    @classmethod
    def setUpClass(cls):
        cls.gate = GATE

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = pathlib.Path(tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        head = shutil.which("head")
        self.assertIsNotNone(head)
        slow = self.bin / "head"
        slow.write_text(f'#!/bin/sh\nsleep 0.4\nexec "{head}" "$@"\n')
        slow.chmod(0o755)

    def replace_after(self, path, content, delay=0.15):
        """Replace path with content in one rename, as the dock's writer does."""
        def worker():
            time.sleep(delay)
            temporary = path.with_name(path.name + ".tmp")
            temporary.write_text(content)
            os.replace(temporary, path)
        thread = threading.Thread(target=worker)
        thread.start()
        return thread

    def run_gate_slow(self, path, cap):
        env = dict(os.environ)
        env["PATH"] = str(self.bin) + os.pathsep + env.get("PATH", "")
        return subprocess.run(["sh", "-c", self.gate, "gate", str(path), str(cap)],
                              capture_output=True, text=True, timeout=10, env=env)

    def test_a_longer_file_landing_mid_read_is_emitted_whole(self):
        path = self.dir / "omadock.json"
        short = '{"autohide": true}'
        path.write_text(short)
        grown = json.dumps({"autohide": True,
                            "presets": [{"id": "preset_1", "name": "Night", "look": {}}]})
        self.assertGreater(len(grown), len(short))
        swap = self.replace_after(path, grown)
        result = self.run_gate_slow(path, 65536)
        swap.join()
        self.assertEqual(result.returncode, 0, result.stderr)
        # The whole file, not the first len(short) bytes of it: the dock parses
        # what comes out of here, and a prefix of a JSON object is not JSON.
        self.assertEqual(result.stdout, grown)
        json.loads(result.stdout)

    def test_a_file_grown_over_the_cap_mid_read_is_refused_not_truncated(self):
        path = self.dir / "omadock.json"
        path.write_text('{"a": 1}')
        swap = self.replace_after(path, "x" * 2000)
        result = self.run_gate_slow(path, 1000)
        swap.join()
        self.assertEqual((result.returncode, result.stdout), (3, ""))


if __name__ == "__main__":
    unittest.main()
