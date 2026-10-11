"""Every animation duration in the dock's QML comes from the motion plan.

A literal duration ignores the Animations setting (Reduced / Off). The
effects that are animations themselves keep their own timings and are
listed here; they are gated by motion.oneShots / motion.reveal instead."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DURATION = re.compile(r"duration:\s*([^;}]+)")


def is_literal(line):
    """A duration with a number in it that does not read the motion plan."""
    m = DURATION.search(line)
    if not m:
        return False
    expr = m.group(1)
    return bool(re.search(r"\d", expr)) and "motion" not in expr and "fadeMs" not in expr
ALLOWED = {
    # launch / urgent bounce and pulse (oneShots)
    ("components/DockItem.qml", "from: 1.0; to: 0.35; duration: 650"),
    ("components/DockItem.qml", "from: 0.35; to: 1.0; duration: 650"),
    ("components/DockItem.qml", "to: -Style.space(13); duration: 260"),
    ("components/DockItem.qml", "to: 0; duration: 260"),
    ("components/DockItem.qml", "PauseAnimation { duration: item.urgent ? 380 : 220 }"),
    # drop-target halo (oneShots)
    ("components/DockItem.qml", "from: 0.5; to: 1.0; duration: 350"),
    ("components/DockItem.qml", "from: 1.0; to: 0.5; duration: 350"),
    ("components/DockAppGroupItem.qml", "from: 0.5; to: 1.0; duration: 350"),
    ("components/DockAppGroupItem.qml", "from: 1.0; to: 0.5; duration: 350"),
    # glow ripple, glitch burst (oneShots)
    ("components/HoverFx.qml", "property: \"ring\""),
    ("components/HoverFx.qml", "property: \"glitchT\""),
    # label typewriter / erase (reveal)
    ("components/DockLabel.qml", "duration: Math.min(300, 25 *"),
    ("components/DockLabel.qml", "id: eraseAnim"),
}


def literals():
    found = []
    for path in [ROOT / "Dock.qml", *sorted((ROOT / "components").glob("*.qml"))]:
        rel = str(path.relative_to(ROOT))
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if is_literal(line) and not any(rel == f and frag in line for f, frag in ALLOWED):
                found.append(f"{rel}:{n}: {line.strip()}")
    return found


class MotionDurations(unittest.TestCase):
    def test_rule(self):
        self.assertTrue(is_literal("NumberAnimation { duration: 120 }"))
        self.assertTrue(is_literal("duration: (root && root.dockVisible) ? 300 : 260"))
        self.assertFalse(is_literal("NumberAnimation { duration: (x.motion ? x.motion.fast : 0) }"))
        self.assertFalse(is_literal("Behavior on level { NumberAnimation { duration: life.fadeMs } }"))

    def test_durations_come_from_motion(self):
        self.assertEqual(literals(), [])


if __name__ == "__main__":
    unittest.main()
