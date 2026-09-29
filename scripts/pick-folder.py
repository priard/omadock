#!/usr/bin/env python3
"""Ask the user for a folder and print its absolute path.

Goes through the XDG FileChooser portal, so the dialog comes from whatever
the desktop routes FileChooser to (e.g. the user's default file manager, if
it ships a portal backend) instead of a hard-wired toolkit dialog. Omarchy's
own `omarchy-file-select` is used when present; otherwise the portal is
called directly. A GTK dialog, zenity and kdialog are the last resorts when
no portal is reachable. Prints nothing when the user cancels.
"""

import random
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlparse

TITLE = "Select Folder to Pin to Dock"


def pick_with_omarchy():
    """omarchy-file-select: 0 picked, 1 nothing picked, 2 chooser failed."""
    if not shutil.which("omarchy-file-select"):
        return False, None
    res = subprocess.run(
        ["omarchy-file-select", "--title", TITLE, "--directory"],
        capture_output=True,
        text=True,
    )
    if res.returncode == 0:
        lines = res.stdout.strip().splitlines()
        return True, (lines[0] if lines else None)
    if res.returncode == 1:
        return True, None
    return False, None


def pick_with_portal():
    """Return (answered, path). answered is False when the portal is unusable."""
    try:
        import gi

        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
    except Exception:
        return False, None

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except Exception:
        return False, None

    token = "omadock%d" % random.randint(0, 2**31)
    sender = bus.get_unique_name().lstrip(":").replace(".", "_")
    request_path = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)

    loop = GLib.MainLoop()
    result = {"answered": False, "path": None}

    def on_response(_conn, _sender, _path, _iface, _signal, params):
        code, results = params.unpack()
        result["answered"] = True
        if code == 0:
            uris = results.get("uris") or []
            if uris:
                parsed = urlparse(uris[0])
                if parsed.scheme == "file":
                    result["path"] = unquote(parsed.path)
        loop.quit()

    # Subscribe before calling, so a fast backend cannot answer unseen.
    sub = bus.signal_subscribe(
        "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request",
        "Response",
        request_path,
        None,
        Gio.DBusSignalFlags.NO_MATCH_RULE,
        on_response,
    )

    options = {
        "handle_token": GLib.Variant("s", token),
        "directory": GLib.Variant("b", True),
        "modal": GLib.Variant("b", True),
    }
    try:
        bus.call_sync(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.FileChooser",
            "OpenFile",
            GLib.Variant("(ssa{sv})", ("", TITLE, options)),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
    except Exception:
        bus.signal_unsubscribe(sub)
        return False, None

    loop.run()
    bus.signal_unsubscribe(sub)
    return result["answered"], result["path"]


def pick_with_gtk():
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
    except Exception:
        return False, None
    dialog = Gtk.FileChooserDialog(title=TITLE, action=Gtk.FileChooserAction.SELECT_FOLDER)
    dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
    chosen = dialog.get_filename() if dialog.run() == Gtk.ResponseType.OK else None
    dialog.destroy()
    return True, chosen


def pick_with_command(argv):
    if not shutil.which(argv[0]):
        return False, None
    res = subprocess.run(argv, capture_output=True, text=True)
    chosen = res.stdout.strip() if res.returncode == 0 else ""
    return True, chosen or None


def main():
    pickers = (
        pick_with_omarchy,
        pick_with_portal,
        pick_with_gtk,
        lambda: pick_with_command(["zenity", "--file-selection", "--directory", "--title=" + TITLE]),
        lambda: pick_with_command(["kdialog", "--getexistingdirectory", "--title", TITLE]),
    )
    for picker in pickers:
        answered, path = picker()
        if answered:
            if path:
                print(path)
            return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
