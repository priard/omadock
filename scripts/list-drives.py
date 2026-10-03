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
