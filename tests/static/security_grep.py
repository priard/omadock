#!/usr/bin/env python3
"""Static security audit for the plugin, as the Omarchy marketplace
reviewers check it. Counts risky patterns per rule and file and compares
them with tests/static/security-baseline.json: a new occurrence fails until
it is reviewed and the baseline updated (--update).

Rules:
  text-format     Text/Label block without textFormat: Text.PlainText
  rich-text       RichText / StyledText / MarkdownText anywhere
  dynamic-code    eval( / new Function( / new RegExp( on non-literals
  shell-concat    "sh"/"bash", "-c", "<literal>" followed by + (data spliced
                  into the command instead of passed as $1..)
  hyprctl-eval    every "hyprctl", "eval" call site (Lua is built from
                  strings; each site needs review)
  notify-send     every notify-send call site (bodies render markup)
  python-c        inline python3 -c programs (move them to scripts/)

Usage: security_grep.py [ROOT] [--update]
"""
import json
import pathlib
import re
import sys

RULES = {
    "rich-text": re.compile(r"\b(RichText|StyledText|MarkdownText)\b"),
    "dynamic-code": re.compile(r"\beval\s*\(|new\s+Function\s*\(|new\s+RegExp\s*\(\s*[^\"'/]"),
    "shell-concat": re.compile(r"\"(ba)?sh\",\s*\"-c\",\s*\"(?:[^\"\\]|\\.)*\"\s*\+"),
    "hyprctl-eval": re.compile(r"\"hyprctl\",\s*\"eval\""),
    "notify-send": re.compile(r"notify-send"),
    "python-c": re.compile(r"\"python3\",\s*\"-c\""),
}
# "Text {", and also "component X: Text {" or "property var p: Label {".
TEXT_OPEN = re.compile(r"(^\s*|:\s*)(Text|Label)\s*\{")


def text_blocks_without_plaintext(src):
    lines = src.splitlines()
    count = 0
    for i, line in enumerate(lines):
        if not TEXT_OPEN.search(line):
            continue
        depth, body = 0, []
        for l in lines[i:]:
            body.append(l)
            depth += l.count("{") - l.count("}")
            if depth <= 0:
                break
        if "Text.PlainText" not in "\n".join(body):
            count += 1
    return count


def scan(root):
    root = pathlib.Path(root)
    out = {}
    files = [p for p in root.rglob("*") if p.suffix in (".qml", ".js", ".py", ".sh")
             and "tests" not in p.relative_to(root).parts and ".git" not in p.parts
             and ".superpowers" not in p.parts and "docs" not in p.relative_to(root).parts]
    for p in sorted(files):
        rel = str(p.relative_to(root))
        try:
            src = p.read_text(errors="replace")
        except OSError:
            continue
        for rule, rx in RULES.items():
            n = len(rx.findall(src))
            if n:
                out[f"{rule}::{rel}"] = n
        if p.suffix == ".qml":
            n = text_blocks_without_plaintext(src)
            if n:
                out[f"text-format::{rel}"] = n
    return dict(sorted(out.items()))


def main(argv):
    args = [a for a in argv[1:] if a != "--update"]
    root = args[0] if args else pathlib.Path(__file__).resolve().parents[2]
    baseline_path = pathlib.Path(__file__).with_name("security-baseline.json")
    now = scan(root)
    if "--update" in argv:
        baseline_path.write_text(json.dumps(now, indent=1) + "\n")
        return 0
    base = json.loads(baseline_path.read_text()) if baseline_path.exists() else {}
    worse = {k: (base.get(k, 0), v) for k, v in now.items() if v > base.get(k, 0)}
    for k, (b, n) in worse.items():
        print(f"security: {k} {b} -> {n}")
    return 1 if worse else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
