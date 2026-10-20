"""Lists every property name the client sets through UIKit (UIKit.new/Label/Button/Panel calls),
so they can be checked against the real Roblox API. The type checker can't see these: they're
plain table keys applied at run time, and one bad name throws and stops the rest of that UI.

    python3 tools/checks/ui_props.py > props.json
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRAPPERS = {"Label": ("TextLabel", {"Children"}), "Button": ("TextButton", {"Children", "CornerRadius"}),
            "Panel": ("Frame", {"Children", "CornerRadius"})}


def table_keys(text, start):
    """Top-level `Key =` names of the table literal opening at text[start] == '{'."""
    depth, i, keys = 0, start, []
    while i < len(text):
        c = text[i]
        if c in "\"'`":
            quote = c
            i += 1
            while i < len(text) and text[i] != quote:
                i += 2 if text[i] == "\\" else 1
        elif text.startswith("--", i):
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        elif c in "{([":
            depth += 1
            if depth == 1 and c == "{":
                pass
        elif c in "})]":
            depth -= 1
            if depth == 0:
                return keys
        elif depth == 1:
            m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)", text[i:])
            if m and (i == 0 or not (text[i - 1].isalnum() or text[i - 1] in "_.")):
                keys.append(m.group(1))
                i += m.end()
                continue
        i += 1
    return keys


def main():
    uses = {}
    for path in sorted((ROOT / "src" / "client").rglob("*.luau")):
        text = path.read_text()
        for m in re.finditer(r'UIKit\.new\(\s*"(\w+)"\s*,\s*\{', text):
            for key in table_keys(text, m.end() - 1):
                if key not in ("Parent", "Children"):
                    uses.setdefault(f"{m.group(1)}.{key}", f"{path.relative_to(ROOT)}:{text[:m.start()].count(chr(10)) + 1}")
        for m in re.finditer(r"UIKit\.(Label|Button|Panel)\(\s*\{", text):
            cls, special = WRAPPERS[m.group(1)]
            for key in table_keys(text, m.end() - 1):
                if key not in special and key != "Parent":
                    uses.setdefault(f"{cls}.{key}", f"{path.relative_to(ROOT)}:{text[:m.start()].count(chr(10)) + 1}")
    json.dump(uses, sys.stdout, indent=1)


if __name__ == "__main__":
    main()
