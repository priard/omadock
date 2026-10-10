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


PLAIN = re.compile(r"^\s*([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)\s*$")
OPEN = re.compile(r"^\s*(?:[a-z]\w*\s*:\s*)?([A-Z]\w*)\s*\{")
PROP = re.compile(r"\bproperty\s+\w+\s+([A-Za-z_]\w*)\b")


def declared(type_name, qml_dir):
    """Properties a plugin QML type declares, or None for a type it does not ship."""
    for path in (qml_dir / "components" / f"{type_name}.qml", qml_dir / f"{type_name}.qml"):
        if path.exists():
            return set(PROP.findall(path.read_text(encoding="utf-8")))
    return None


def own_property_reads(text, props_of):
    """`rootRef: root` inside `BadgeMark { ... }`, where BadgeMark declares its
    own `root`: the right-hand name resolves on BadgeMark itself, not on the
    file's object of that name. props_of(type) gives a type's declared
    properties (None when unknown)."""
    lines = text.splitlines()
    ids = {m.group(1) for m in (ID.match(l) for l in lines) if m}
    stack, out = [], []
    for n, line in enumerate(lines, 1):
        m = PLAIN.match(line)
        if m and stack and m.group(2) not in ids and m.group(2) not in ("true", "false", "null", "undefined"):
            props = props_of(stack[-1])
            if props and m.group(2) in props:
                out.append((n, line.strip()))
        o = OPEN.match(line)
        if o:
            stack.append(o.group(1))
        opened = line.count("{") - (1 if o else 0)
        for _ in range(max(0, opened)):
            stack.append(None)
        for _ in range(line.count("}")):
            if stack:
                stack.pop()
    return out


class SelfBinding(unittest.TestCase):
    def test_rule(self):
        self.assertEqual(self_bindings("Item {\n  Page { root: root }\n  Page {\n    root: root\n  }\n}"),
                         [(4, "root: root")])
        self.assertEqual(self_bindings("Item {\n  id: panel\n  Page {\n    panel: panel\n  }\n}"), [])

    def test_own_property_rule(self):
        props = {"Badge": {"rootRef", "root", "count"}}.get
        src = ("Item {\n  readonly property var root: rootRef\n  Badge {\n    rootRef: root\n    count: total\n  }\n"
               "  Other {\n    rootRef: root\n  }\n}")
        self.assertEqual(own_property_reads(src, props), [(4, "rootRef: root")])
        self.assertEqual(own_property_reads("Item {\n  id: root\n  Badge {\n    rootRef: root\n  }\n}", props), [])

    def test_tree_own_property_reads(self):
        found = []
        for path in sorted(QML_DIR.rglob("*.qml")):
            if "docs" in path.parts:
                continue
            for n, line in own_property_reads(path.read_text(encoding="utf-8"), lambda t: declared(t, QML_DIR)):
                found.append(f"{path.relative_to(QML_DIR)}:{n}: {line}")
        self.assertEqual(found, [])

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
