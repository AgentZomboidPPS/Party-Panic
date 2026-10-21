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
MODULES = ["Build", "Shapes", "MeshAssets", "MeshLibrary", "Environment", "Arcade", "LobbyBuilder", "BeachBalls"]
# World/Props modules the lobby uses (the mini-games' own props are skipped).
PROPS = ["Lobby", "Arcade"]
# Shared modules the World modules need that a published place may not have yet.
SHARED = ["Logic/SkeeBall"]


def shared_requires(text: str) -> str:
    """require(ReplicatedStorage.Shared.Logic.X) -> the bundled copy, for the modules in SHARED."""
    def swap(match):
        path = match.group(1).replace(".", "/")
        return f'__require("Shared/{path}")' if path in SHARED else match.group(0)

    return re.sub(r"require\(ReplicatedStorage\.Shared\.([\w.]+)\)", swap, text)


def module_source(name: str) -> str:
    text = (WORLD / f"{name}.luau").read_text()
    text = shared_requires(text)
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'__require("\1")', text)
    # World/Props: only the modules in PROPS, served from the bundle.
    text = text.replace('script.Parent:FindFirstChild("Props")', "__propsFolder")
    text = text.replace("require(module :: any)(helpers)", "__props[module.Name](helpers)")
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
        "local __props = {}",
        "local __propsFolder = {",
        "\tGetChildren = function(_self)",
        "\t\tlocal list = {}",
        "\t\tfor name in __props do",
        "\t\t\ttable.insert(list, { Name = name, IsA = function(_, class) return class == \"ModuleScript\" end })",
        "\t\tend",
        "\t\treturn list",
        "\tend,",
        "}",
    ]
    for name in SHARED:
        out.append(f'__modules["Shared/{name}"] = function()')
        out.append(re.sub(r"^export type", "type", (ROOT / "src" / "shared" / f"{name}.luau").read_text(), flags=re.M))
        out.append("end")
    for name in PROPS:
        source = (WORLD / "Props" / f"{name}.luau").read_text()
        out.append(f'__props["{name}"] = (function()')
        out.append(source)
        out.append("end)()")
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
