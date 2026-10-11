"""A bare `Color` stays the shell's singleton on a newer QtQuick.

Qt 6.12 added a `Color` singleton to QtQuick. An unqualified `Color` in a file
that imports QtQuick without a version then resolves to that new type, while
every file here is written against the shell's `qs.Commons` singleton -
`Color.accent`, `Color.menu.text`, and the theme signals in
`Dock.qml`'s `Connections { target: Color }`. The failure is silent in the
sense that matters: the dock still instantiates and answers IPC, but every
colour it asks for is `undefined` (`Cannot read property 'background' of
undefined`, 221 lines in the dock's own log on Qt 6.12.0), so the surface
renders wrong. The convention is to import QtQuick with the version the
plugin is built and verified against, which keeps the shadowing type out of
scope.

The check is on the use, not the import: a file that never touches `Color`
may import QtQuick bare. QML_DIR overrides the tree (to check the rule can
fail).
"""
import os
import pathlib
import re
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
QML_DIR = pathlib.Path(os.environ.get("QML_DIR", ROOT))

# A bare `Color` use: `Color.accent`, `Color.bar.background`, `target: Color`.
# Not the word inside a string (the "Color" settings label), and not part of a
# longer identifier (labelColor, onThemeChanged).
COLOR_USE = re.compile(r'(?<![A-Za-z0-9_."])Color(?![A-Za-z0-9_"])')
BARE_IMPORT = re.compile(r"^import\s+QtQuick\s*$", re.M)
PINNED = re.compile(r"^import\s+QtQuick\s+6\.(\d+)\s*$", re.M)
# 6.12 is the version that introduces the shadowing singleton.
MAX_MINOR = 11


def violations(directory):
    """Every .qml file whose bare `Color` use is not protected by a version pin."""
    found = []
    for path in sorted(directory.rglob("*.qml")):
        rel = str(path.relative_to(directory))
        text = path.read_text(encoding="utf-8")
        if not COLOR_USE.search(text):
            continue
        if BARE_IMPORT.search(text):
            found.append(f"{rel}: bare 'import QtQuick' - Color would resolve to Qt 6.12's singleton")
            continue
        pins = [int(m.group(1)) for m in PINNED.finditer(text)]
        if not pins or min(pins) > MAX_MINOR:
            found.append(f"{rel}: QtQuick is not pinned to at most 6.{MAX_MINOR}")
    return found


class QtQuickColorShadowing(unittest.TestCase):
    def test_every_color_user_pins_its_qtquick_import(self):
        self.assertEqual(violations(QML_DIR), [])

    def test_the_rule_can_fail(self):
        """Both halves catch their shape, and a clean file stays clean."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            (tmp / "Bare.qml").write_text(
                "import QtQuick\n\nItem { color: Color.accent }\n", encoding="utf-8")
            (tmp / "TooNew.qml").write_text(
                "import QtQuick 6.12\n\nItem { color: Color.accent }\n", encoding="utf-8")
            (tmp / "Pinned.qml").write_text(
                "import QtQuick 6.11\n\nItem { color: Color.accent }\n", encoding="utf-8")
            (tmp / "NoColor.qml").write_text(
                'import QtQuick\n\nItem { color: "#000" }\n', encoding="utf-8")
            caught = violations(tmp)
            self.assertEqual(len(caught), 2, caught)
            self.assertIn("Bare.qml", caught[0])
            self.assertIn("TooNew.qml", caught[1])


if __name__ == "__main__":
    unittest.main()
