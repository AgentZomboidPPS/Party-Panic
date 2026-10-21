"""Runs a Luau script on a real Roblox server (Open Cloud Luau execution) and saves its results.

    python3 tools/preview/bundle.py > task.luau
    python3 tools/preview/luau_task.py task.luau - dump.json      # "-" = latest place version

Needs an Open Cloud key with Luau execution access to the experience (ROBLOX_API_KEY, or a proxy
that adds it). The script runs in a fresh server: the game's own scripts don't start, and nothing
is saved, so it can't change the live game.
"""
import os
import json, random, re, sys, time, urllib.request, urllib.error
U = int(os.environ.get("PP_UNIVERSE_ID", "10772087888"))
P = int(os.environ.get("PP_PLACE_ID", "78868713931081"))
RETRY_FOR = 1800  # seconds to keep retrying when Roblox says "too many requests" (429) or is briefly down (5xx)
def req(method, url, body=None):
    headers = {"Content-Type": "application/json"}
    if os.environ.get("ROBLOX_API_KEY"):
        headers["x-api-key"] = os.environ["ROBLOX_API_KEY"]
    data = None if body is None else json.dumps(body).encode()
    give_up = time.time() + RETRY_FOR
    wait = 4
    while True:
        r = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(r, timeout=120) as resp:
                return json.loads(resp.read() or b"{}")
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:2000]
            if (e.code == 429 or e.code >= 500) and time.time() < give_up:
                # Starting a task is capped at 5 a minute for everyone sharing the place, and a 429 says
                # when that minute is up: try again just after it, a random moment later, so a task
                # that has waited long has the same chance as a new one (a doubling wait left it trying
                # once a minute while newcomers tried every few seconds, and it starved).
                reset = re.match(r"\s*(\d+)", e.headers.get("X-Ratelimit-Reset") or "") if e.code == 429 else None
                if reset:
                    pause = int(reset.group(1)) + random.uniform(0.2, 3)
                else:
                    pause = wait + random.uniform(0, wait / 2)
                    wait = min(wait * 2, 60)
                print(f"busy ({e.code}), retrying in {pause:.0f}s", file=sys.stderr)
                time.sleep(pause)
                continue
            sys.exit(f"{method} {url}: HTTP {e.code} {detail}")
        except (urllib.error.URLError, TimeoutError) as e:
            if time.time() < give_up:
                print(f"network error ({e}), retrying in {wait}s", file=sys.stderr)
                time.sleep(wait)
                wait = min(wait * 2, 60)
                continue
            raise
def run(script, version=None, timeout="300s"):
    base = f"https://apis.roblox.com/cloud/v2/universes/{U}/places/{P}"
    if version: base += f"/versions/{version}"
    task = req("POST", base + "/luau-execution-session-tasks", {"script": script, "timeout": timeout})
    path = task["path"]
    while task.get("state") not in ("COMPLETE", "FAILED", "CANCELLED"):
        time.sleep(5)  # many agents share the rate limit: don't poll faster
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
