"""Picks the modules a harness bundle needs (tools/checks/round_harness.py, client_harness.py).

Open Cloud caps a Luau execution script at 1 MiB, and every game adds shared modules that every
mode's bundle used to carry (Shark Bait's round bundle reached 990 KB with three more games on the
way). A bundle now holds only what its run can load: the modules the harness's own Luau asks for,
and everything those reach, followed through

- `__require("X")`: the static requires the harnesses rewrite (require(script.Parent.X),
  require(Shared.X), ...);
- `__folder("F")`: a folder lookup (script.Parent:FindFirstChild("Props"), script.Parent.Parent.
  MiniGames) lists the bundled modules directly in F, so all of them come along (MeshLibrary loads
  every Props file it finds, so the borrowed ones too; MiniGameController its round's client half);
- in the harness's own Luau, `__require("Server/MiniGames/" .. id)` and the like: the run's mode,
  its bot brain (and Default), and every controller it names.

Any other require is one the bundler can't follow by its text: each is listed in DYNAMIC_REQUIRES
with what it loads, and a new one stops the build (BundleError) until it's listed, as does a static
require of a module that isn't there. A missing module fails at build time, not halfway through a
Roblox task.
"""

from __future__ import annotations

import re

LITERAL = re.compile(r'__require\(\s*"([^"]+)"\s*\)|pcall\(\s*__require\s*,\s*"([^"]+)"\s*\)')
PREFIXED = re.compile(r'(?:__require\(\s*|pcall\(\s*__require\s*,\s*)"([^"]*)"\s*\.\.')
FOLDER = re.compile(r'__folder\(\s*"([^"]+)"\s*\)')
# A require that's still a require after the rewrite (the harnesses turn the ones they can follow
# into __require("...")): require(x), pcall(require, x), and their __req forms.
DYNAMIC = re.compile(r'(?<![\w.])(?:__req|require)\s*\(|pcall\(\s*(?:__req|require)\s*,')

# Every require in the game's code that the bundler can't follow by its text: (module, a pattern its
# line matches after the rewrite, what it loads and why the bundle still has it). "*" is any module.
DYNAMIC_REQUIRES = [
    (
        "Server/World/MeshLibrary",
        r"(?:__req|require)\(module :: any\)\(helpers\)",
        "every Props/<File> it finds through script.Parent:FindFirstChild(\"Props\") (a __folder listing)",
    ),
    (
        "Server/MiniGames",
        r"pcall\((?:__req|require), child\)",
        "the game's mode registry requires its own children (modes, bots); in a harness `script` is "
        "the task, which has none, so it loads nothing",
    ),
    (
        "Client/Controllers/MiniGameController",
        r"pcall\((?:__req|require), moduleScript\)",
        "the round's client half through script.Parent.Parent.MiniGames (a __folder listing)",
    ),
    (
        "*",
        r"(?:__req|require)\(module(?: :: any)?\).*:GetControls\(\)",
        "Roblox's own PlayerModule (PlayerScripts), not a bundled module",
    ),
]


class BundleError(Exception):
    pass


def _code(line: str) -> str:
    """A line without its trailing comment (good enough here: no string in this code holds "--")."""
    return line.split("--", 1)[0]


def audit(name: str, body: str):
    """Raises BundleError for a require in a rewritten module body that the bundler can't follow
    and DYNAMIC_REQUIRES doesn't explain."""
    for number, line in enumerate(body.split("\n"), start=1):
        code = _code(line)
        if not DYNAMIC.search(code):
            continue
        if any((module in ("*", name)) and re.search(pattern, code) for module, pattern, _ in DYNAMIC_REQUIRES):
            continue
        raise BundleError(
            f"{name}:{number}: a require the bundler can't follow: {line.strip()}\n"
            "  Use require(script...) or require(Shared...), or list it in DYNAMIC_REQUIRES "
            "(tools/checks/bundling.py) with what it loads."
        )


def seeds(text: str, game: str, available: dict, roots: set) -> set:
    """The modules a harness's own Luau (prelude, bot, scenario) asks for: by name, plus the ones it
    builds from a prefix (the run's mode, its bot brain and Default, every controller and service it
    names).
    A name under a root this run bundles (Shared, Server, and Client with --client) must exist."""
    found = set()
    text = "\n".join(_code(line) for line in text.split("\n"))
    for a, b in LITERAL.findall(text):
        name = a or b
        if name in available:
            found.add(name)
        elif name.split("/")[0] in roots:
            raise BundleError(f"the harness asks for {name}, which isn't in the bundle")
    for prefix in set(PREFIXED.findall(text)):
        if prefix == "Server/MiniGames/":
            wanted = [f"Server/MiniGames/{game}"]
        elif prefix == "Server/MiniGames/Bots/":
            wanted = [f"Server/MiniGames/Bots/{game}", "Server/MiniGames/Bots/Default"]
        elif prefix == "Client/Controllers/":
            wanted = [f"Client/Controllers/{n}" for n in re.findall(r'"(\w+Controller)"', text)]
        elif prefix == "Server/Services/":  # the round harness starts the services it names (CupService...)
            wanted = [f"Server/Services/{n}" for n in re.findall(r'"(\w+Service)"', text)]
        else:
            raise BundleError(f'the harness requires "{prefix}" .. something: tell tools/checks/bundling.py which ones')
        found.update(name for name in wanted if name in available)
    return found


def closure(available: dict, start: set, provided: set = frozenset()) -> set:
    """The modules reachable from `start` in `available` (name -> rewritten body). `provided` are
    modules the harness defines itself (its Remotes stand-in)."""
    keep: set = set()
    todo = list(start)
    while todo:
        name = todo.pop()
        if name in keep:
            continue
        keep.add(name)
        body = available[name]
        audit(name, body)
        for target in LITERAL.findall(body):
            target = target[0] or target[1]
            if target in provided:
                continue
            if target not in available:
                raise BundleError(f"{name} requires {target}, which isn't in the bundle (another mode's module?)")
            todo.append(target)
        for folder in FOLDER.findall(body):
            prefix = folder + "/"
            todo.extend(n for n in available if n.startswith(prefix) and "/" not in n[len(prefix):])
    return keep
