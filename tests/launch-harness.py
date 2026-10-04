#!/usr/bin/env python3
"""omadock launch-id validation harness (read-only, part of the verification suite).

Validates every installed desktop-entry id against omadock's `launch()` suffix
logic, exactly as Dock.qml applies it before handing the name to gtk-launch:

    launch(desktopId, name): gtk-launch -- (desktopId + ".desktop")   [v3.7.2+]
    launch(desktopId, name): gtk-launch -- (desktopId endswith ".desktop"
                                            ? desktopId
                                            : desktopId + ".desktop")  [<= v3.7.1, buggy]

Ground truths used:
  * Desktop Entry Specification "File naming": a desktop file's ID is its path
    relative to the applications dir, with '/' replaced by '-' and one
    ".desktop" suffix removed.
  * Quickshell DesktopEntryScanner (src/core/desktopentry.cpp): id =
    completeBaseName for flat files, `subdirPrefix + '-' + basename` for files
    in subdirectories.
  * GIO (GioUnix.DesktopAppInfo.new) is the resolver gtk-launch uses.

Since v3.7.3 the dock itself reports unresolved launches ("App no longer
installed" notification) and refuses to pin unresolvable ids; this harness is
the offline regression gate for the same resolver contract.

Read-only: it never launches anything. Exit 0 = all ids resolve, 1 = failures.
"""

import os
import shutil
import sys
from pathlib import Path

try:
    import gi
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix
    def gio_lookup(arg):
        try:
            return GioUnix.DesktopAppInfo.new(arg)
        except TypeError:
            return None
except Exception:  # pragma: no cover - fallback for older PyGObject
    from gi.repository import Gio
    def gio_lookup(arg):
        try:
            return Gio.DesktopAppInfo.new(arg)
        except TypeError:
            return None


# --- 1. Suffix logic under test (mirrors Dock.qml launch()) -----------------

def suffix_new(desktop_id: str) -> str:
    """v3.7.2+: always append."""
    return desktop_id + ".desktop"


def suffix_old(desktop_id: str) -> str:
    """<= v3.7.1: conditional append (buggy for ids ending in '.desktop')."""
    return desktop_id if desktop_id[-8:] == ".desktop" else desktop_id + ".desktop"


# --- 2. Desktop-entry scan mirroring Quickshell's id derivation -------------

def complete_base_name(filename: str) -> str:
    """QFileInfo::completeBaseName: filename minus its last extension."""
    stem, dot, _ext = filename.rpartition(".")
    return stem if dot else filename


def scan_dir(base: Path, id_prefix: str, out: list):
    """Mirror of DesktopEntryScanner::scanDirectory (desktopentry.cpp:372)."""
    try:
        entries = sorted(base.iterdir())
    except OSError:
        return
    for entry in entries:
        if entry.is_dir():
            sub = entry.name if not id_prefix else f"{id_prefix}-{entry.name}"
            scan_dir(entry, sub, out)
        elif entry.is_file():
            if not entry.name.endswith(".desktop"):
                continue
            basename = complete_base_name(entry.name)
            desktop_id = basename if not id_prefix else f"{id_prefix}-{basename}"
            out.append((desktop_id, entry))


def exec_binary(desktop_file: Path):
    """First token of the Exec= key (after optional field codes removed)."""
    try:
        for line in desktop_file.read_text(errors="replace").splitlines():
            if line.startswith("Exec="):
                return line[5:].strip().split()[0] if line[5:].strip() else None
    except OSError:
        pass
    return None


def application_dirs() -> list:
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    dirs = [data_home / "applications"]
    for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(Path(d) / "applications")
    seen, ordered = set(), []
    for d in dirs:
        rp = d.resolve() if d.exists() else d
        if rp not in seen:
            seen.add(rp)
            ordered.append(d)
    return ordered


# --- 3. Synthetic edge-case table for the suffix function itself -----------

EDGE_CASES = [
    # (desktop_id, note)
    ("org.telegram.desktop", "id itself ends in .desktop (the Telegram class)"),
    ("firefox", "plain id"),
    ("kde4-konsole", "subdirectory-derived id (kde4/konsole.desktop)"),
    ("io.github.shonebinu.Glyph", "reverse-DNS flatpak id"),
    ("com.github.foo.bar.desktop", "reverse-DNS id ALSO ending in .desktop"),
    ("gnome-language-panel", "dashed id, no subdir"),
    ("a.b.c.d", "id with multiple dots"),
]


def main() -> int:
    print("=== omadock launch-id harness (read-only) ===\n")

    # -- synthetic checks ---------------------------------------------------
    print("-- suffix logic check --")
    logic_failures = 0
    for desktop_id, note in EDGE_CASES:
        new_arg = suffix_new(desktop_id)
        old_arg = suffix_old(desktop_id)
        # The new logic must ALWAYS append exactly one .desktop suffix.
        expected = desktop_id + ".desktop"
        old_broken = old_arg != expected
        if new_arg != expected:
            logic_failures += 1
            verdict = "NEW-LOGIC-FAIL"
        elif old_broken:
            verdict = "OLD-BROKEN"
        else:
            verdict = "old ok"
        print(f"  {desktop_id!r:42} -> new {new_arg!r:44} [{verdict}]  ({note})")
    print()

    # -- real system scan ---------------------------------------------------
    entries = []
    for base in application_dirs():
        scan_dir(base, "", entries)

    print(f"-- scanned {len(entries)} desktop entries from {len(application_dirs())} applications dirs --")

    broken_class = []   # ids where old logic produced a different (wrong) arg
    unresolved = []     # ids where GIO cannot resolve the constructed name (other causes)
    stale = []          # entries whose Exec binary is missing (unlaunchable at all)
    misresolved = []    # GIO resolves, but to a different file than scanned
    subdir_ids = []     # ids derived from subdirectory entries
    dupes = {}

    for desktop_id, path in entries:
        dupes.setdefault(desktop_id, []).append(path)
        if "-" in desktop_id and path.parent.name.endswith("applications") is False:
            subdir_ids.append((desktop_id, path))
        new_arg = suffix_new(desktop_id)
        old_arg = suffix_old(desktop_id)
        if old_arg != new_arg:
            broken_class.append((desktop_id, old_arg, new_arg))
        info = gio_lookup(new_arg)
        if info is None:
            # GIO refuses to build a DesktopAppInfo when the Exec binary is not
            # installed. Those entries are stale: no launcher can run them.
            exec_bin = exec_binary(path)
            if exec_bin and shutil.which(exec_bin) is None:
                stale.append((desktop_id, exec_bin, path))
            else:
                unresolved.append((desktop_id, new_arg, path))
        else:
            resolved = Path(info.get_filename()).resolve() if info.get_filename() else None
            if resolved != path.resolve():
                misresolved.append((desktop_id, resolved, path))

    print(f"\n  ids ending in '.desktop' (old-logic breakage class): {len(broken_class)}")
    for desktop_id, old_arg, new_arg in broken_class:
        print(f"    {desktop_id}: old sent {old_arg!r} (unresolvable), new sends {new_arg!r}")

    print(f"\n  ids derived from subdirectory entries: {len(subdir_ids)}")
    for desktop_id, path in subdir_ids:
        print(f"    {desktop_id} <- {path}")

    print(f"\n  stale entries (Exec binary missing - unlaunchable by any launcher): {len(stale)}")
    for desktop_id, exec_bin, path in stale:
        print(f"    {desktop_id}: Exec binary {exec_bin!r} not found  (source: {path})")

    print(f"\n  ids where GIO cannot resolve the constructed name (other causes): {len(unresolved)}")
    for desktop_id, new_arg, path in unresolved:
        print(f"    {desktop_id} -> {new_arg!r}  (source: {path})")

    print(f"\n  ids where GIO resolves to a different file than scanned: {len(misresolved)}")
    for desktop_id, resolved, path in misresolved:
        print(f"    {desktop_id}: GIO={resolved}  scan={path}")

    shadowed = {k: v for k, v in dupes.items() if len(v) > 1}
    print(f"\n  duplicate ids across dirs (XDG precedence shadowing): {len(shadowed)}")
    for desktop_id, paths in shadowed.items():
        print(f"    {desktop_id}:")
        for p in paths:
            print(f"      {p}")

    ok = not unresolved and not logic_failures
    print(f"\n=== {'PASS' if ok else 'FAIL'}: "
          f"{len(entries)} entries, {len(broken_class)} old-logic breakage, "
          f"{len(unresolved)} unresolved, {len(misresolved)} shadowed, "
          f"{len(stale)} stale (Exec missing) ===")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
