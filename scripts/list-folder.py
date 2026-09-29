#!/usr/bin/env python3
"""List a folder for a dock stack as JSON.

Usage: list-folder.py FOLDER [SORT]

SORT is one of:
  name      natural, case-insensitive name order
  kind      by type (folders first, then extension), then name
  modified  newest modification first (default)
  added     newest first by when the entry landed in the folder; Linux has
            no "date added", and the inode change time (ctime) is the closest
            stand-in: moving or downloading a file into a folder sets it
  size      largest first (folders count as 0)

Prints {"count": N, "items": [...first 16...], "folder": FOLDER}. Hidden
entries are skipped. The output is always valid JSON, even for a missing
folder.
"""

import json
import os
import re
import sys
import time

LIMIT = 16
SORTS = ("name", "kind", "modified", "added", "size")

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"}
VIDEO_EXT = {".mp4", ".mkv", ".webm", ".mov", ".avi"}
AUDIO_EXT = {".mp3", ".flac", ".wav", ".ogg", ".m4a"}
ARCHIVE_EXT = {".zip", ".tar", ".gz", ".xz", ".7z", ".rar"}
TEXT_EXT = {".txt", ".md", ".json", ".qml", ".py", ".cpp", ".js", ".lua", ".rs", ".go", ".html", ".css"}


def human_size(n):
    if n < 1024:
        return "%d B" % n
    if n < 1024 ** 2:
        return "%.1f KB" % (n / 1024)
    if n < 1024 ** 3:
        return "%.1f MB" % (n / 1024 ** 2)
    return "%.1f GB" % (n / 1024 ** 3)


def human_age(ts):
    diff = time.time() - ts
    if diff < 60:
        return "Just now"
    if diff < 3600:
        return "%dm ago" % (diff // 60)
    if diff < 86400:
        return "%dh ago" % (diff // 3600)
    return "%dd ago" % (diff // 86400)


def icon_for(ext, is_dir):
    if is_dir:
        return "folder"
    if ext in IMAGE_EXT:
        return "image-x-generic"
    if ext in VIDEO_EXT:
        return "video-x-generic"
    if ext in AUDIO_EXT:
        return "audio-x-generic"
    if ext in ARCHIVE_EXT:
        return "package-x-generic"
    if ext == ".pdf":
        return "application-pdf"
    if ext in TEXT_EXT:
        return "text-x-generic"
    return "application-x-executable"


def natural_key(name):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", name.casefold())]


def main():
    folder = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else ""
    sort = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] in SORTS else "modified"

    entries = []
    if folder and os.path.isdir(folder):
        try:
            scan = list(os.scandir(folder))
        except OSError:
            scan = []
        for entry in scan:
            if entry.name.startswith("."):
                continue
            try:
                st = entry.stat()
                is_dir = entry.is_dir()
            except OSError:
                continue
            ext = "" if is_dir else os.path.splitext(entry.name)[1].lower()
            size = 0 if is_dir else st.st_size
            entries.append({
                "name": entry.name,
                "path": entry.path,
                "isDir": is_dir,
                "isImage": ext in IMAGE_EXT,
                "size": human_size(size),
                "time": human_age(st.st_mtime),
                "mtime": st.st_mtime,
                "icon": icon_for(ext, is_dir),
                "_ext": ext,
                "_bytes": size,
                "_ctime": st.st_ctime,
            })

    if sort == "name":
        entries.sort(key=lambda e: natural_key(e["name"]))
    elif sort == "kind":
        entries.sort(key=lambda e: (not e["isDir"], e["_ext"], natural_key(e["name"])))
    elif sort == "added":
        entries.sort(key=lambda e: e["_ctime"], reverse=True)
    elif sort == "size":
        entries.sort(key=lambda e: (e["_bytes"], e["mtime"]), reverse=True)
    else:
        entries.sort(key=lambda e: e["mtime"], reverse=True)

    items = [{k: v for k, v in e.items() if not k.startswith("_")} for e in entries[:LIMIT]]
    print(json.dumps({"count": len(entries), "items": items, "folder": folder, "sort": sort}))


if __name__ == "__main__":
    main()
