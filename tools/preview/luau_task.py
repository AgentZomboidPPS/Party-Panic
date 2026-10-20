"""Runs a Luau script on a real Roblox server (Open Cloud Luau execution) and saves its results.

    python3 tools/preview/bundle.py > task.luau
    python3 tools/preview/luau_task.py task.luau - dump.json      # "-" = latest place version

Needs an Open Cloud key with Luau execution access to the experience (ROBLOX_API_KEY, or a proxy
that adds it). The script runs in a fresh server: the game's own scripts don't start, and nothing
is saved, so it can't change the live game.
"""
import os
import json, sys, time, urllib.request, urllib.error
U = int(os.environ.get("PP_UNIVERSE_ID", "10772087888"))
P = int(os.environ.get("PP_PLACE_ID", "78868713931081"))
def req(method, url, body=None):
    headers = {"Content-Type": "application/json"}
    if os.environ.get("ROBLOX_API_KEY"):
        headers["x-api-key"] = os.environ["ROBLOX_API_KEY"]
    r = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), method=method, headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url}: HTTP {e.code} {e.read().decode()[:2000]}")
def run(script, version=None, timeout="300s"):
    base = f"https://apis.roblox.com/cloud/v2/universes/{U}/places/{P}"
    if version: base += f"/versions/{version}"
    task = req("POST", base + "/luau-execution-session-tasks", {"script": script, "timeout": timeout})
    path = task["path"]
    while task.get("state") not in ("COMPLETE", "FAILED", "CANCELLED"):
        time.sleep(3)
        task = req("GET", "https://apis.roblox.com/cloud/v2/" + path)
    logs = req("GET", "https://apis.roblox.com/cloud/v2/" + path + "/logs")
    return task, logs
if __name__ == "__main__":
    script = open(sys.argv[1]).read()
    version = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "-" else None
    task, logs = run(script, version)
    out = sys.argv[3] if len(sys.argv) > 3 else None
    print("state", task.get("state"), "error", json.dumps(task.get("error"))[:3000])
    for chunk in logs.get("luauExecutionSessionTaskLogs", []):
        for m in chunk.get("messages", [])[-80:]:
            print("LOG", str(m)[:400])
    res = (task.get("output") or {}).get("results")
    if out:
        json.dump(res, open(out, "w"))
        print("saved results to", out)
    else:
        print(json.dumps(res)[:3000])
