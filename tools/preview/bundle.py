"""Bundles the working-tree World modules and dump_world.luau into one Luau script for Open Cloud
Luau execution, so lobby changes can be previewed without publishing a place version.

    python3 tools/preview/bundle.py > /tmp/task.luau
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "src" / "server" / "World"
MODULES = ["Build", "Shapes", "MeshAssets", "MeshLibrary", "Environment", "LobbyBuilder"]


def module_source(name: str) -> str:
    text = (WORLD / f"{name}.luau").read_text()
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'__require("\1")', text)
    # Type exports are only legal at the top level; inside the wrapper they become local types.
    text = re.sub(r"^export type", "type", text, flags=re.M)
    return text


def main():
    out = [
        "local __modules = {}",
        "local __cache = {}",
        "local function __require(name: string): any",
        "\tif __cache[name] == nil then",
        "\t\t__cache[name] = __modules[name]()",
        "\tend",
        "\treturn __cache[name]",
        "end",
    ]
    for name in MODULES:
        out.append(f'__modules["{name}"] = function()')
        out.append(module_source(name))
        out.append("end")
    out.append("do")
    out.append((ROOT / "tools" / "preview" / "dump_world.luau").read_text())
    out.append("end")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
