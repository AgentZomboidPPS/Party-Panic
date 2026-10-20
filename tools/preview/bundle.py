"""Bundles the working-tree World modules and dump_world.luau into one Luau script for Open Cloud
Luau execution, so lobby changes can be previewed without publishing a place version.

    python3 tools/preview/bundle.py > /tmp/task.luau
    python3 tools/preview/bundle.py my_check.luau > /tmp/task.luau   # run your own script instead
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
    # The lobby doesn't use the mini-games' own props (World/Props), so skip loading them.
    text = text.replace('script.Parent:FindFirstChild("Props")', "nil")
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
    script = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tools" / "preview" / "dump_world.luau"
    out.append("do")
    out.append(script.read_text())
    out.append("end")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
