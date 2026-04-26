#!/usr/bin/env bash
# Run a single v10 regression iteration in the background and write
# stable PID/LOG paths so the orchestrator can poll without re-evaluating
# date globs through PowerShell.
set -u

HERE="$(dirname "$0")"
ROOT="$(cd "$HERE/.." && pwd)"
LOG_DIR="$ROOT/experiment_log"
mkdir -p "$LOG_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
RUN_TAG="${RUN_TAG:-run0}"

LOG="$LOG_DIR/regression_v10_${RUN_TAG}_${TS}.log"
JSON="$LOG_DIR/regression_v10_${RUN_TAG}_${TS}.json"
ATT="$LOG_DIR/regression_v10_${RUN_TAG}_${TS}_attempts"
mkdir -p "$ATT"

PIDFILE="$LOG_DIR/regression_v10_${RUN_TAG}.pid"
LOG_PTR="$LOG_DIR/regression_v10_${RUN_TAG}.lastlog"
JSON_PTR="$LOG_DIR/regression_v10_${RUN_TAG}.lastjson"

nohup env V5_OUT="$JSON" V5_LOG_DIR="$ATT" \
  python3 "$HERE/regression_v5.py" >"$LOG" 2>&1 &

echo $! > "$PIDFILE"
echo "$LOG" > "$LOG_PTR"
echo "$JSON" > "$JSON_PTR"

echo "PID=$(cat "$PIDFILE")"
echo "LOG=$LOG"
echo "JSON=$JSON"
echo "ATT=$ATT"
