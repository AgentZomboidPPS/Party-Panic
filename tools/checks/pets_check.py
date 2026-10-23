"""Builds a Luau script that checks the crate season's pets (Shared/Seasons: HOLLOW NIGHT's five) on a
real Roblox server (Open Cloud Luau execution), with the round harness's stand-in players and the
working tree's code: tools/checks/pets_check.luau loads the pets' uploaded meshes through
World/MeshLibrary, runs Controllers/PetController as a device does, and samples every pet standing,
running and through its flourish. (Owner: "For all of these pets. They all have super cool
animations right?")

    python3 tools/checks/pets_check.py > pets.luau
    python3 tools/preview/luau_task.py pets.luau - pets.json

The result's "checks" lists every check (ok / FAIL with what it saw), "failed" the names of those that
failed, "measures" what was sampled (per pet: each group's largest turn in degrees, how far each
Hinge drifted in studs, the body's lowest and highest point over its owner's root, its steepest
pitch), "errors" every error and warning the run logged.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bundling  # noqa: E402
import round_harness  # noqa: E402  (its module rewriting and prelude: the stand-in players, remotes)

CHECK = Path(__file__).resolve().parent / "pets_check.luau"


def main():
    header = "__touchMode = false\n__noCsg = false\n"
    paths = {**round_harness.module_paths(), **round_harness.client_paths()}
    available = {}
    for module, path in paths.items():
        if module == "Shared/Remotes" or round_harness.other_mode(module, ""):
            continue  # the harness's Remotes stand-in; no mini-game is played
        available[module] = round_harness.slim(round_harness.rewrite(module, path.read_text(), path.name == "init.luau"))
    check = CHECK.read_text()
    harness = round_harness.PRELUDE_RAW + "\n" + check
    try:
        start = bundling.seeds(round_harness.reachable_luau(harness, "__runPets"), "", available,
                               {"Shared", "Server", "Client"})
        keep = bundling.closure(available, start, provided={"Shared/Remotes"})
    except bundling.BundleError as err:
        sys.exit(f"pets_check: {err}")
    out = [header + round_harness.PRELUDE]
    for module, body in available.items():
        if module in keep:
            out.append(f'__modules["{module}"] = function()')
            out.append(body)
            out.append("end")
    out.append(check)
    out.append("return __runPets()")
    sys.stdout.write("\n".join(out))


if __name__ == "__main__":
    main()
