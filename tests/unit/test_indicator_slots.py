"""The indicator row declares exactly the slots it draws.

A Qt Grid reserves a gap for every slot it is told to have, not only for the
children it holds: `Grid { columns: 8 }` with one 5 px child measures 12 px
wide at spacing 7. The marks row is centred on its icon, so those phantom
slots pushed every dot half a gap to the left (2 px on a 1.33 font scale) -
the drift between the marks and the icon art. The row therefore has to bind
its column and row count to the number of marks it draws, plus the overflow
pill, and never to a literal.

INDICATOR_ROW overrides the file under test (to check the test can fail).
"""
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ROW = pathlib.Path(os.environ.get("INDICATOR_ROW",
                   ROOT / "components" / "DockIndicatorRow.qml"))
SLOT = re.compile(r"^\s*(columns|rows)\s*:\s*(.+?)\s*$")
PROP = re.compile(r"^\s*readonly\s+property\s+int\s+(\w+)\s*:\s*(.+?)\s*$")


def grid_block(text):
    """The body of the file's first Grid, or "" when there is none."""
    lines = text.splitlines()
    start = next((n for n, l in enumerate(lines) if re.match(r"^\s*Grid\s*\{", l)), None)
    if start is None:
        return []
    depth = 0
    out = []
    for line in lines[start:]:
        depth += line.count("{") - line.count("}")
        out.append(line)
        if depth <= 0:
            break
    return out


def slot_bindings(block):
    return [(m.group(1), m.group(2)) for l in block if (m := SLOT.match(l))]


def properties(text):
    return {m.group(1): m.group(2) for l in text.splitlines() if (m := PROP.match(l))}


class IndicatorSlots(unittest.TestCase):
    def test_rule(self):
        # A literal slot count is the bug: it reserves the empty slots.
        block = ["  Grid {", "    columns: 8", "    rows: 1", "  }"]
        self.assertEqual(slot_bindings(block), [("columns", "8"), ("rows", "1")])
        self.assertTrue(all("slots" not in value for _, value in slot_bindings(block)))

    def test_row_declares_only_the_slots_it_draws(self):
        text = ROW.read_text(encoding="utf-8")
        block = grid_block(text)
        self.assertTrue(block, f"no Grid found in {ROW}")
        bindings = slot_bindings(block)
        self.assertEqual(sorted(k for k, _ in bindings), ["columns", "rows"])
        for key, value in bindings:
            self.assertIn("slotCount", value,
                          f"{key}: {value} must come from the row's own slot count")
        props = properties(text)
        self.assertIn("slotCount", props, "the row must name its slot count")
        slots = props["slotCount"]
        # One slot per visible mark, one for the overflow pill, at least one.
        self.assertIn("Math.max(1,", slots)
        self.assertIn("maxVisibleDots", slots)
        self.assertIn("totalWindowCount > 5", slots)
        # The pill the count reserves a slot for is the one actually drawn.
        self.assertIn("visible: marks.totalWindowCount > 5", text)
        self.assertIn('"+"', text)


if __name__ == "__main__":
    unittest.main()
