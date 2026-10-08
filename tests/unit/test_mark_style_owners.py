"""The size of a mark has one owner (DockMarkGeometry.js).

A size spelled out in a component silently disagreed with the other places that
draw the same mark or reserve room for it - the family of the row that declared
a grid slot it did not draw. This asserts the arithmetic, not a spelling: a
component may not size a mark itself, whatever it names its properties or the
module's functions.

The row and the indicator draw marks and nothing else, so neither may call
Style.space itself - they pass the resolver to the module, the way a label
passes its measuring function to DockLabels. The label lays out a name and has
spacing of its own, so only the room it reserves for the marks' column is
checked, anchored on those property names: a renamed property would slip past.
The check catches the shape this file was written against; it cannot prove the
absence of every possible one.

QML_DIR overrides the directory (to check that the tests can fail).
"""
import os
import pathlib
import re
import shutil
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
QML_DIR = pathlib.Path(os.environ.get("QML_DIR", ROOT))
MODULE = "DockMarkGeometry"
MARKS_ONLY = ["components/DockIndicatorRow.qml", "components/DockIndicator.qml"]
LABEL = "components/DockLabel.qml"
# The room a plate reserves: the shape that used to be its own copy of the
# marks' size.
LABEL_ROOM = re.compile(r"^\s*(?:readonly\s+property\s+\w+\s+)?mark(?:Edge|Width|Gap)\s*:.*Style\.space\(")
# The arithmetic that used to live in a component: a mark size chosen by density
# or a side column and snapped onto the pixel grid there.
OLD_SHAPE = ("  property real oldCross: Math.max(snap(Style.space((dense || vertical) ? 4 : 5)), "
             "snap(Style.space(4)))\n")


def size_it_itself(directory):
    """Lines where a component sizes a mark itself, in the shape the module owns."""
    found = []
    for rel in MARKS_ONLY:
        for n, line in enumerate((directory / rel).read_text(encoding="utf-8").splitlines(), 1):
            if "Style.space(" in line:
                found.append(f"{rel}:{n} sizes a mark itself: {line.strip()}")
    for n, line in enumerate((directory / LABEL).read_text(encoding="utf-8").splitlines(), 1):
        if LABEL_ROOM.match(line):
            found.append(f"{LABEL}:{n} reserves the column's room itself: {line.strip()}")
    return found


class MarkSizeOwners(unittest.TestCase):
    def test_every_consumer_reads_the_module(self):
        for rel in MARKS_ONLY + [LABEL]:
            text = (QML_DIR / rel).read_text(encoding="utf-8")
            self.assertIn(f'import "../{MODULE}.js" as {MODULE}', text,
                          f"{rel} must import {MODULE}.js")
            self.assertRegex(text, rf"{MODULE}\.\w+\(",
                             f"{rel} must take its mark sizes from {MODULE}.js")

    def test_no_component_sizes_a_mark_itself(self):
        self.assertEqual(size_it_itself(QML_DIR), [])

    def test_the_rule_can_fail(self):
        """The old shape, on a copy of the tree, is caught: not a vacuous rule."""
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            for rel in MARKS_ONLY + [LABEL]:
                (tmp / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(QML_DIR / rel, tmp / rel)
            row = tmp / MARKS_ONLY[0]
            row.write_text(row.read_text(encoding="utf-8") + OLD_SHAPE, encoding="utf-8")
            caught = size_it_itself(tmp)
            self.assertEqual(len(caught), 1, f"the old shape must be caught once: {caught}")
            self.assertIn("sizes a mark itself", caught[0])


if __name__ == "__main__":
    unittest.main()
