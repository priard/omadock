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
