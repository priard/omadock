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
            args = log.read_text().splitlines()
            # Options first, then "--": a label like "-u..." must not be
            # parsed as a notify-send option.
            self.assertEqual(args[:5], ["-a", "omadock", "-i", "drive-removable-media", "--"])
            self.assertEqual(args[6], "a href='x'Evil/a can now be safely disconnected.")

    def test_falls_back_when_notify_send_is_broken(self):
        # The regression this exists for: hosts where notify-send fails at
        # startup (libnotify ABI mismatch) must still deliver the warning,
        # through Omarchy's sender, with the dash label still one text
        # positional after the static headline.
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = pathlib.Path(tmp)
            log = bin_dir / "notify.log"
            (bin_dir / "gio").write_text("#!/bin/sh\nexit 0\n")
            (bin_dir / "notify-send").write_text("#!/bin/sh\nexit 1\n")
            (bin_dir / "omarchy-notification-send").write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > {log}\n')
            for f in ("gio", "notify-send", "omarchy-notification-send"):
                os.chmod(bin_dir / f, 0o755)
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            r = subprocess.run([sys.executable, str(SCRIPTS / "eject-drive.py"), "/dev/sdz1",
                                "/run/media/u/x", "-uc"],
                               capture_output=True, text=True, env=env, timeout=30)
            self.assertEqual(r.stdout.strip(), "True")
            args = log.read_text().splitlines()
            self.assertEqual(args[:4], ["--app-name", "omadock", "-i", "drive-removable-media"])
            self.assertEqual(args[4], "Device Safely Removed")
            self.assertEqual(args[5], "-uc can now be safely disconnected.")

    def test_label_starting_with_a_dash_stays_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir = pathlib.Path(tmp)
            log = bin_dir / "notify.log"
            (bin_dir / "gio").write_text("#!/bin/sh\nexit 0\n")
            (bin_dir / "notify-send").write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > {log}\n')
            for f in ("gio", "notify-send"):
                os.chmod(bin_dir / f, 0o755)
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
            subprocess.run([sys.executable, str(SCRIPTS / "eject-drive.py"), "/dev/sdz1",
                            "/run/media/u/x", "-uc"], capture_output=True, text=True, env=env, timeout=30)
            args = log.read_text().splitlines()
            self.assertLess(args.index("--"), args.index("-uc can now be safely disconnected."))


if __name__ == "__main__":
    unittest.main()
