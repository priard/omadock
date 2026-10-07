#!/usr/bin/env python3
"""Maintainability structure check (AGENTS.md "Maintainability Rules").

Rules enforced:
  1. File-size cap: every .qml/.js/.mjs file is at most MAX_LINES lines.
  2. Composition roots (Dock.qml, DockModel.js) are the only exceptions and
     carry ratchet ceilings: they may shrink over time, never grow. Lowering
     a ceiling is part of any refactor that moves code out of a root.
  3. components/logic/*.qml are pure logic: QtObject with functions only -
     no timers, processes, file views, windows, or visual items.
  4. components/logic/*.qml functions take the owner root as the FIRST
     parameter (`root`), keeping every module call uniform.

Exit codes: 0 = all rules hold; 1 = violations (printed one per line).
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

MAX_LINES = 800

# Composition roots: single-owner state + wiring must live somewhere, and it
# lives here. These ceilings are ratchets - see rule 2.
ROOT_CEILINGS = {
    "Dock.qml": 2408,
    "DockModel.js": 1529,
}

# Rule 3: objects that belong in the composition root or in a visual
# component, never in a logic module.
FORBIDDEN_IN_LOGIC = re.compile(
    r"^\s*(Timer|Process|CappedFileView|PanelWindow|Window|Connections|Repeater|"
    r"ListView|Flickable|Rectangle|Image|Loader|LazyLoader|MouseArea|"
    r"WheelHandler|DragHandler|HoverHandler|TapHandler)\s*\{")

# Rule 4: module functions take `root` first.
ROOT_FIRST = re.compile(r"^  function [A-Za-z_]\w*\((?!root[,)])")

SKIP_DIRS = {".git", "node_modules", "__pycache__"}


def source_files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix not in {".qml", ".js", ".mjs"}:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        yield path


def main():
    violations = []
    for path in source_files():
        rel = path.relative_to(ROOT).as_posix()
        lines = path.read_text(errors="replace").splitlines()
        cap = ROOT_CEILINGS.get(rel, MAX_LINES)
        if len(lines) > cap:
            kind = "root ratchet" if rel in ROOT_CEILINGS else "file-size cap"
            violations.append(f"{rel}: {len(lines)} lines exceeds {kind} of {cap}")
        if rel.startswith("components/logic/"):
            for n, line in enumerate(lines, 1):
                if FORBIDDEN_IN_LOGIC.search(line):
                    violations.append(
                        f"{rel}:{n}: logic module declares {line.strip()} "
                        f"- timers/processes/visuals belong in Dock.qml or a component")
                if line.startswith("  function ") and ROOT_FIRST.match(line):
                    violations.append(
                        f"{rel}:{n}: logic function must take `root` as first parameter")

    if violations:
        print("structure-check FAILED:")
        for v in violations:
            print("  " + v)
        print(f"\n{len(violations)} violation(s). See AGENTS.md "
              f"\"Maintainability Rules\". Composition-root ceilings may only "
              f"be lowered, never raised.")
        return 1
    print("structure-check PASSED: no file exceeds its cap; "
          "logic modules are pure.")
    return 0


sys.exit(main())
