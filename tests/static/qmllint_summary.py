#!/usr/bin/env python3
"""Reduce qmllint --json output to warning counts per file and category,
and compare against a baseline: only new categories or higher counts fail.
'unqualified' and 'import' are noise here (the Omarchy shell's qs.* modules
are not visible to qmllint)."""
import json
import sys

NOISE = {"unqualified", "import"}


def summary(path):
    data = json.load(open(path))
    out = {}
    for f in data.get("files", []):
        name = f.get("filename", "").split("/omadock/")[-1]
        for w in f.get("warnings", []):
            cat = w.get("id") or w.get("type") or "unknown"
            if cat in NOISE:
                continue
            key = f"{name}::{cat}"
            out[key] = out.get(key, 0) + 1
    return dict(sorted(out.items()))


def main(argv):
    if argv[1] == "--compare":
        base, now = json.load(open(argv[2])), json.load(open(argv[3]))
        worse = {k: (base.get(k, 0), v) for k, v in now.items() if v > base.get(k, 0)}
        for k, (b, n) in worse.items():
            print(f"qmllint: {k} {b} -> {n}")
        return 1 if worse else 0
    print(json.dumps(summary(argv[1]), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
