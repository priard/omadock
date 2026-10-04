#!/usr/bin/env python3
"""Safely remove a drive: gio, then udisksctl, then umount.

Usage: eject-drive.py DEV MOUNTPOINT NAME
Prints True or False; on success sends a notification naming the drive
(label cleaned: notification bodies render markup).
"""

import os
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
            # notify.sh picks Omarchy's own sender when present (plain
            # notify-send is broken on some hosts and would drop this), and
            # keeps options like "-u..." from being read as flags.
            subprocess.run(["bash", os.path.join(os.path.dirname(os.path.abspath(__file__)), "notify.sh"),
                            "drive-removable-media", "Device Safely Removed",
                            f"{name} can now be safely disconnected."])
        except OSError:
            pass
    print(ok)


if __name__ == "__main__":
    main(sys.argv)
