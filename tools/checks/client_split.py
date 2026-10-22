"""Runs the whole-client harness in parts when its result is too big for one Open Cloud task.

Open Cloud caps a task's result at 4 MiB, and a result near that (the harness's UI snapshots grow with
every game and screen) fails as "INTERNAL_ERROR Task timed out due to an internal error" after
600 s; past it, as OUTPUT_SIZE_LIMIT_EXCEEDED. Each part returns every check but only its share of
the UI snapshots (sorted by name, dealt out in turn); `merge` joins them into one result, like an
unsplit run, for ui_render.py.

    python3 tools/checks/client_harness.py --touch > client.luau
    python3 tools/checks/client_split.py split client.luau client-part 3      # client-part-0.luau ...
    python3 tools/preview/luau_task.py client-part-0.luau - client-part-0.json  # each part in turn
    python3 tools/checks/client_split.py merge client.json client-part-*.json
    python3 tools/checks/ui_render.py client.json ui-touch
"""

import json
import sys

RETURN = 'return game:GetService("HttpService"):JSONEncode({'


def split(bundle: str, prefix: str, parts: int):
    text = open(bundle).read()
    if text.count(RETURN) != 1:
        sys.exit("can't find the harness's final return in " + bundle)
    for part in range(parts):
        keep = (
            "do\n"
            "\tlocal names = {}\n"
            "\tfor name in __ui do\n\t\ttable.insert(names, name)\n\tend\n"
            "\ttable.sort(names)\n"
            "\tlocal kept = {}\n"
            f"\tfor index, name in names do\n\t\tif index % {parts} == {part} then\n\t\t\tkept[name] = __ui[name]\n\t\tend\n\tend\n"
            "\t__ui = kept\n"
            "end\n"
        )
        with open(f"{prefix}-{part}.luau", "w") as out:
            out.write(text.replace(RETURN, keep + RETURN))
    print(f"{parts} parts: {prefix}-0.luau .. {prefix}-{parts - 1}.luau")


def merge(out: str, parts: list[str]):
    merged = None
    for path in parts:
        results = json.load(open(path))
        if not results:
            sys.exit(f"a part failed (see its task log): {path}")
        data = json.loads(results[0]) if isinstance(results[0], str) else results[0]
        if merged is None:
            merged = data
        else:
            merged["ui"].update(data.get("ui") or {})
    json.dump([json.dumps(merged)], open(out, "w"))
    print(f"merged {len(merged['ui'])} snapshots from {len(parts)} parts into {out}")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "split":
        split(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 2)
    elif len(sys.argv) >= 4 and sys.argv[1] == "merge":
        merge(sys.argv[2], sys.argv[3:])
    else:
        sys.exit(__doc__)
