#!/usr/bin/env python3
"""The English catalog, i18n/en.json, as the code defines it.

Keys come from explicit calls (Tr.t / Tr.tn, and tr in JS modules that take
the translator) and from the keys the settings UI derives on its own:

  setting.<key>.label / .hint      a settings row with a key and literal text
  setting.<key>.option.<value>     a ChoiceRow option written as a literal
  section.<slug>                   a SectionLabel title ("Dock Items" -> dock-items)
  page.<id>                        a SettingsPanel page
  search.<key>                     a search entry with no row or section label
  menu.sort.<key>, folderColor.*   the label maps in Dock.qml and DockContextLogic

  python3 tests/static/i18n-en.py           rewrite i18n/en.json (keys it holds
                                            that the code no longer yields stay)
  python3 tests/static/i18n-en.py --check   fail when a key is missing or its
                                            English differs (CI)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
EN = ROOT / "i18n" / "en.json"
STR = r'"((?:[^"\\]|\\.)*)"'


def text(raw):
    return json.loads('"' + raw + '"')


def slug(title):
    return re.sub(r"^-|-$", "", re.sub(r"[^a-z0-9]+", "-", title.lower()))


def code_catalog():
    cat, problems = {}, []

    def put(key, value):
        if key in cat and cat[key] != value:
            problems.append(f"{key}: two English texts, {cat[key]!r} and {value!r}")
        cat.setdefault(key, value)

    for path in sorted(list(ROOT.glob("**/*.qml")) + list(ROOT.glob("**/*.js"))):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(("tests/", "bench/", "docs/", ".")):
            continue
        src = path.read_text(encoding="utf-8")
        for m in re.finditer(r"\b(?:Tr\.t|tr)\(\s*" + STR + r"\s*,\s*" + STR, src):
            put(m.group(1), text(m.group(2)))
        for m in re.finditer(r"Tr\.tn\(\s*" + STR + r"\s*,[^?]*\?\s*" + STR + r"\s*:\s*" + STR, src):
            put(m.group(1), {"one": text(m.group(2)), "other": text(m.group(3))})

    for path in sorted((ROOT / "components" / "settings").glob("Settings*.qml")):
        src = path.read_text(encoding="utf-8")
        lines = src.split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"^(\s*)(ChoiceRow|SwitchRow|SliderRow|SettingRow)\s*\{", line)
            if not m:
                continue
            indent, block = len(m.group(1)), []
            for nxt in lines[i + 1:]:
                if re.match(r"^\s{%d}\}" % indent, nxt):
                    break
                block.append(nxt)
            own = [b for b in block if re.match(r"^\s{%d}\S" % (indent + 2), b)]
            key = next((re.match(r'\s*key: "([^"]+)"', b).group(1) for b in own if re.match(r'\s*key: "', b)), "")
            if not key:
                continue
            for b in own:
                mm = re.match(r'\s*(label|hint): ' + STR + r"\s*$", b)
                if mm:
                    put(f"setting.{key}.{mm.group(1)}", text(mm.group(2)))
            if m.group(2) == "ChoiceRow":
                for mm in re.finditer(r'\{ value: "([^"]*)", label: ' + STR + r" \}", "\n".join(block)):
                    put(f"setting.{key}.option.{mm.group(1)}", text(mm.group(2)))
        for mm in re.finditer(r'SectionLabel \{[^}]*?title: "([^"]+)"', src):
            put("section." + slug(mm.group(1)), mm.group(1))

    panel = (ROOT / "components" / "SettingsPanel.qml").read_text(encoding="utf-8")
    for mm in re.finditer(r'\{ id: "([^"]+)", label: "([^"]+)", glyph', panel):
        put("page." + mm.group(1), mm.group(2))

    search = (ROOT / "SettingsSearch.js").read_text(encoding="utf-8")
    for mm in re.finditer(r'\{ key: "([^"]+)", page: "[^"]+", label: "([^"]+)"', search):
        if f"setting.{mm.group(1)}.label" not in cat and "section." + slug(mm.group(2)) not in cat:
            put("search." + mm.group(1), mm.group(2))

    dock = (ROOT / "Dock.qml").read_text(encoding="utf-8")
    sort = dock[dock.index("folderSortLabels: ({"):]
    for mm in re.finditer(r'(\w+): "([^"]+)"', sort[:sort.index("})")]):
        put("menu.sort." + mm.group(1), mm.group(2))

    ctx = (ROOT / "components" / "logic" / "DockContextLogic.qml").read_text(encoding="utf-8")
    colors = ctx[ctx.index("function folderColorLabel"):]
    for mm in re.finditer(r'"(Yaru-[a-z]+)": "([^"]+)"', colors[:colors.index("return map")]):
        put("folderColor." + mm.group(1), mm.group(2))

    return cat, problems


def main():
    cat, problems = code_catalog()
    current = json.loads(EN.read_text(encoding="utf-8")) if EN.exists() else {}
    if "--check" in sys.argv:
        for key, value in cat.items():
            if key not in current:
                problems.append(f"{key}: missing from i18n/en.json")
            elif current[key] != value:
                problems.append(f"{key}: i18n/en.json has {current[key]!r}, the code {value!r}")
        for p in problems:
            print("i18n:", p)
        print(f"i18n-en {'FAILED' if problems else 'PASSED'}: {len(cat)} keys from the code")
        return 1 if problems else 0
    for p in problems:
        print("i18n:", p, file=sys.stderr)
    merged = dict(current)
    merged.update(cat)
    EN.write_text(json.dumps(dict(sorted(merged.items())), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {EN.relative_to(ROOT)}: {len(merged)} keys")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
