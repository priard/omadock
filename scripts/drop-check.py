#!/usr/bin/env python3
"""Can an application open the files dragged onto its dock icon?

Usage: drop-check.py DESKTOP_ID PATH...

Prints "yes" when the application's desktop entry lists a MIME type (its
MimeType= key) for every path, "no" otherwise, including when the entry
cannot be found or lists no MIME types at all. A path's type is what GIO
reports for it (the same detection file managers use), and it counts as
supported when it is, or inherits from, a listed type (text/x-python is a
text/plain), or matches a wildcard such as image/*. Folders are
inode/directory.
"""

import sys

try:
    import gi

    gi.require_version("Gio", "2.0")
    from gi.repository import Gio
except Exception:
    print("no")
    sys.exit(0)

# Newer GLib moved DesktopAppInfo to GioUnix; older ones only have Gio's.
try:
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix

    DesktopAppInfo = GioUnix.DesktopAppInfo
except Exception:
    DesktopAppInfo = Gio.DesktopAppInfo


def app_info(desktop_id):
    for candidate in (desktop_id, desktop_id.lower()):
        candidates = [candidate + ".desktop"]
        if candidate.endswith(".desktop"):
            candidates.append(candidate)
        for name in candidates:
            try:
                info = DesktopAppInfo.new(name)
            except TypeError:
                info = None
            if info:
                return info
    return None


def content_type(path):
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        return info.get_content_type() or ""
    except Exception:
        return ""


def supported(ctype, types):
    for t in types:
        if t.endswith("/*"):
            if ctype.startswith(t[:-1]):
                return True
        elif ctype == t or Gio.content_type_is_a(ctype, t):
            return True
    return False


def main():
    if len(sys.argv) < 3:
        print("no")
        return
    info = app_info(sys.argv[1])
    types = list(info.get_supported_types() or []) if info else []
    if not types:
        print("no")
        return
    for path in sys.argv[2:]:
        ctype = content_type(path)
        if not ctype or not supported(ctype, types):
            print("no")
            return
    print("yes")


if __name__ == "__main__":
    main()
