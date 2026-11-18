#!/usr/bin/env bash
# Bring SPECTRE up in the background (dashboard, live feeds and KAIROS) and return.
#
# Safe to run again and again: it does nothing if SPECTRE is already up. It installs SPECTRE
# first if this machine does not have it, so it is all a fresh container needs. With Alpaca
# credentials (in .env, or supplied by the hosting environment) a new database is rebuilt from
# the broker's own records; without them SPECTRE only listens and shows the dashboard, rather
# than quietly trading a simulated book in the real one's place.
#
# State lives in $SPECTRE_HOME (default ~/.spectre): the database, the log, and an optional
# `env` file of settings to apply (for example SPECTRE_DATABASE_URL or SPECTRE_PORTFOLIO).
#
#   scripts/start_cloud.sh               start in the background and return (a server, a VM)
#   scripts/start_cloud.sh --foreground  stay attached, for a supervisor that tracks the
#                                        process itself. Some hosted sessions pause the machine
#                                        when nothing they track is running, which kills a
#                                        process that was merely left in the background.
set -euo pipefail
cd "$(dirname "$0")/.."
FOREGROUND=false
[ "${1:-}" = "--foreground" ] && FOREGROUND=true

STATE="${SPECTRE_HOME:-$HOME/.spectre}"
mkdir -p "$STATE"
if [ -f "$STATE/env" ]; then set -a; . "$STATE/env"; set +a; fi
PORT="${PORT:-8765}"

if pgrep -f "spectre run" >/dev/null && curl -fsS -m 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "SPECTRE is already running on port $PORT."
  exit 0
fi

if command -v spectre >/dev/null 2>&1 && spectre run --help >/dev/null 2>&1; then
  SPECTRE=spectre
else
  if [ ! -x "$STATE/venv/bin/spectre" ]; then
    python3 -m venv "$STATE/venv"
    "$STATE/venv/bin/pip" install --quiet -e .
  fi
  SPECTRE="$STATE/venv/bin/spectre"
fi

# Older pieces started separately would trade the same account twice.
pkill -f "spectre (serve|autopilot|ingest|run)( |$)" 2>/dev/null || true

export SPECTRE_DATABASE_URL="${SPECTRE_DATABASE_URL:-sqlite:///$STATE/spectre.db}"
# Remember where the database is, so other commands (`spectre report`, `spectre risk`) can be
# pointed at the same one with:  set -a; . "$STATE/env"; set +a
[ -f "$STATE/env" ] || printf 'SPECTRE_DATABASE_URL=%s\nPORT=%s\n' "$SPECTRE_DATABASE_URL" "$PORT" > "$STATE/env"
export SPECTRE_REQUIRE_ALPACA="${SPECTRE_REQUIRE_ALPACA:-true}"
export PYTHONUNBUFFERED=1 COLUMNS=170
if $FOREGROUND; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) starting in the foreground" >> "$STATE/run.log"
  exec "$SPECTRE" run --port "$PORT" >> "$STATE/run.log" 2>&1
fi
nohup setsid "$SPECTRE" run --port "$PORT" >> "$STATE/run.log" 2>&1 &

if curl -fsS --retry 45 --retry-delay 2 --retry-connrefused -m 5 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "SPECTRE is up on port $PORT. Log: $STATE/run.log"
  grep -a "SPECTRE is up\|Rebuilt the ledger\|Picked up\|listening only\|Could not" "$STATE/run.log" | tail -4 || true
else
  echo "SPECTRE did not come up. Last lines of $STATE/run.log:"
  tail -20 "$STATE/run.log" || true
  exit 1
fi
