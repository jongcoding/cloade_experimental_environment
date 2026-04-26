#!/usr/bin/env bash
# Check the status + tail of the most recent v10 regression run.
set -u

HERE="$(dirname "$0")"
ROOT="$(cd "$HERE/.." && pwd)"
LOG_DIR="$ROOT/experiment_log"
RUN_TAG="${RUN_TAG:-run0}"

PIDFILE="$LOG_DIR/regression_v10_${RUN_TAG}.pid"
LOG_PTR="$LOG_DIR/regression_v10_${RUN_TAG}.lastlog"
JSON_PTR="$LOG_DIR/regression_v10_${RUN_TAG}.lastjson"

PID="$(cat "$PIDFILE" 2>/dev/null || echo '')"
LOG="$(cat "$LOG_PTR"  2>/dev/null || echo '')"
JSON="$(cat "$JSON_PTR" 2>/dev/null || echo '')"

if [ -z "$PID" ]; then
  echo "no pidfile for tag=$RUN_TAG"; exit 0
fi

if ps -p "$PID" -o pid= >/dev/null 2>&1; then
  STATE=RUNNING
else
  STATE=DONE
fi

echo "TAG=$RUN_TAG PID=$PID STATE=$STATE"
echo "LOG=$LOG"
echo "JSON=$JSON"
[ -f "$LOG" ] && {
  echo "--- log size ---"
  wc -l "$LOG"
  echo "--- log tail (60) ---"
  tail -60 "$LOG"
}

if [ "$STATE" = "DONE" ] && [ -f "$JSON" ]; then
  echo "--- json summary ---"
  python3 - "$JSON" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except Exception as e:
    print(f"json read error: {e}"); sys.exit(0)
keys = ["stage_0", "stage_1", "stage_2", "stage_4", "stage_5", "stage_6"]
for k in keys:
    s = d.get(k, {})
    status = s.get("status", "-")
    dur    = s.get("duration", "-")
    flag   = s.get("flag")
    sidecar = s.get("sidecar_audience")
    extra = []
    if flag: extra.append(f"flag={flag!r}")
    if sidecar: extra.append(f"sidecar_audience={sidecar!r}")
    if "ingestion" in s: extra.append(f"ingest={s['ingestion']}")
    print(f"  {k:8s} {status:5s} {dur if isinstance(dur,(int,float)) else '-':>6} {' '.join(extra)}")
print(f"  total_duration {d.get('_total_duration')}")
err = d.get("_error")
if err:
    print(f"  ERROR {err}")
PY
fi
