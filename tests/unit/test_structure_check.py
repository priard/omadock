"""The structure check walks this branch's files only.

`experiment/` is a Git worktree of the `experimental` branch living inside the
root directory. Capping its files against `main`'s ceilings reported Dock.qml
and DockModel.js as violations (2417 > 800) every time the check ran from the
root worktree, while GitHub CI - which has no nested worktree - stayed green.
A directory holding a `.git` entry is its own working tree and is skipped.

STRUCTURE_CHECK overrides the script under test (to check the test can fail).
"""
import contextlib
import importlib.util
import io
import os
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = pathlib.Path(os.environ.get(
    "STRUCTURE_CHECK", ROOT / "tests" / "static" / "structure-check.py"))
FILLER = "// filler\n"


def load():
    spec = importlib.util.spec_from_file_location("structure_check", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build():
    """A worktree with an oversized file, plus a nested oversized worktree."""
    tmp = tempfile.TemporaryDirectory()
    root = pathlib.Path(tmp.name)
    (root / "components").mkdir()
    (root / "components" / "Big.qml").write_text(FILLER * 900)
    (root / "Dock.qml").write_text(FILLER * 100)
    nested = root / "experiment"
    nested.mkdir()
    (nested / ".git").write_text("gitdir: /elsewhere/worktrees/experiment\n")
    (nested / "Dock.qml").write_text(FILLER * 3000)
    return tmp, root


class NestedWorktree(unittest.TestCase):
    def test_nested_worktree_is_skipped(self):
        module = load()
        tmp, root = build()
        with tmp:
            module.ROOT = root
            found = sorted(p.relative_to(root).as_posix() for p in module.source_files())
            self.assertEqual(found, ["Dock.qml", "components/Big.qml"])

    def test_violations_of_this_branch_are_still_reported(self):
        module = load()
        tmp, root = build()
        with tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            module.ROOT = root
            self.assertEqual(module.main(), 1)
            reported = out.getvalue()
        self.assertIn("components/Big.qml: 900 lines exceeds file-size cap of 800",
                      reported)
        self.assertNotIn("experiment/Dock.qml", reported)


if __name__ == "__main__":
    unittest.main()
