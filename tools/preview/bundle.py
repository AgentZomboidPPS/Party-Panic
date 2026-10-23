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
MODULES = ["Build", "Shapes", "MeshAssets", "MeshLibrary", "Environment", "LobbyObby", "Arcade", "HallOfFame",
           "MedalWall", "EventDecor", "Hats", "SeasonWorld", "LobbyBuilder", "BeachBalls"]
SHARED_DIR = ROOT / "src" / "shared"
# World/Props modules the lobby uses (the mini-games' own props are skipped).
PROPS = ["Lobby", "Arcade", "HollowNight"]  # (HollowNight: the crate season's pile, altars and dressing)

# A Shared module asked for by its path from ReplicatedStorage (ReplicatedStorage.Shared.Logic.X,
# game:GetService("ReplicatedStorage").Shared.X, or a local Shared = ReplicatedStorage.Shared).
SHARED_REQUIRE = re.compile(r'require\((?:game:GetService\("ReplicatedStorage"\)\.|ReplicatedStorage\.)?Shared\.([\w.]+)\)')


def to_type(text: str) -> str:
    # Type exports are only legal at the top level; inside the wrapper they become local types.
    return re.sub(r"^export type", "type", text, flags=re.M)


def module_source(name: str) -> str:
    text = (WORLD / f"{name}.luau").read_text()
    text = re.sub(r"require\(script\.Parent\.(\w+)\)", r'__require("\1")', text)
    # Shared modules come from the working tree too (a saved place version may not have them yet).
    text = SHARED_REQUIRE.sub(lambda m: f'__require("Shared/{m.group(1).replace(".", "/")}")', text)
    # World/Props: only the modules in PROPS, served from the bundle.
    text = text.replace('script.Parent:FindFirstChild("Props")', "__propsFolder")
    text = text.replace("require(module :: any)(helpers)", "__props[module.Name](helpers)")
    return to_type(text)


def shared_source(path: str) -> str:
    """A Shared module (path like "Logic/MedalLogic"), its own requires (script.Parent...) pointed at
    the bundle's copies."""
    folder = path.split("/")[:-1]  # script.Parent: the folder the module is in

    def resolve(match: re.Match) -> str:
        parts = match.group(1).split(".")  # what follows script.Parent, e.g. Parent, Config
        base = list(folder)
        while parts and parts[0] == "Parent":  # each further Parent is one folder up
            base = base[:-1]
            parts = parts[1:]
        return f'__require("Shared/{"/".join(base + parts)}")'

    text = (SHARED_DIR / f"{path}.luau").read_text()
    text = re.sub(r"require\(script\.Parent\.([\w.]+)\)", resolve, text)
    return to_type(text)


def shared_needed() -> list[str]:
    """Every Shared module the World modules need, with the ones those need in turn."""
    found: list[str] = []
    todo = [m.group(1).replace(".", "/") for name in MODULES for m in SHARED_REQUIRE.finditer((WORLD / f"{name}.luau").read_text())]
    while todo:
        path = todo.pop()
        if path in found:
            continue
        found.append(path)
        todo += re.findall(r'__require\("Shared/([\w/]+)"\)', shared_source(path))
    return sorted(found)


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
    for name in PROPS:
        source = (WORLD / "Props" / f"{name}.luau").read_text()
        out.append(f'__props["{name}"] = (function()')
        out.append(source)
        out.append("end)()")
    for path in shared_needed():
        out.append(f'__modules["Shared/{path}"] = function()')
        out.append(shared_source(path))
        out.append("end")
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
