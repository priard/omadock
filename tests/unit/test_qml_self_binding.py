"""No QML binding that resolves to the property it sets.

Inside `Child { root: root }` the right-hand `root` is looked up on Child
first, so when Child declares `property var root` the binding reads its own
property and stays null. Ids are looked up before the object's properties,
so `panel: panel` with `id: panel` in the same file is fine. QML_DIR
overrides the directory (to check that the test can fail)."""
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
QML_DIR = pathlib.Path(os.environ.get("QML_DIR", ROOT))
SELF = re.compile(r"^\s*([A-Za-z_]\w*)\s*:\s*\1\s*$")
ID = re.compile(r"^\s*id\s*:\s*([A-Za-z_]\w*)\s*$")


def self_bindings(text):
    lines = text.splitlines()
    ids = {m.group(1) for m in (ID.match(l) for l in lines) if m}
    out = []
    for n, line in enumerate(lines, 1):
        m = SELF.match(line)
        if m and m.group(1) not in ids:
            out.append((n, line.strip()))
    return out


class SelfBinding(unittest.TestCase):
    def test_rule(self):
        self.assertEqual(self_bindings("Item {\n  Page { root: root }\n  Page {\n    root: root\n  }\n}"),
                         [(4, "root: root")])
        self.assertEqual(self_bindings("Item {\n  id: panel\n  Page {\n    panel: panel\n  }\n}"), [])

    def test_tree(self):
        found = []
        for path in sorted(QML_DIR.rglob("*.qml")):
            if "docs" in path.parts:
                continue
            for n, line in self_bindings(path.read_text(encoding="utf-8")):
                found.append(f"{path.relative_to(QML_DIR)}:{n}: {line}")
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
