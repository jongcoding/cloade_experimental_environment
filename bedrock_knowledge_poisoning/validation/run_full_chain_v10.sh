#!/usr/bin/env bash
# v10 full-chain regression runner.
#
# Usage:
#   bash validation/run_full_chain_v10.sh                # one run
#   bash validation/run_full_chain_v10.sh --runs 3       # three back-to-back runs (3/3 PASS bar)
#   bash validation/run_full_chain_v10.sh --skip-clean   # don't delete attacker leftovers between runs
#
# Each run produces:
#   experiment_log/regression_v10_run<N>_<TS>.log     (stdout/stderr)
#   experiment_log/regression_v10_run<N>_<TS>.json    (regression_v5.py result)
#   experiment_log/regression_v10_run<N>_stage{4,6}_attempts.json
#
# A run is considered PASS only if every Stage 0/1/2/4/5/6 reported PASS in
# the result json. Stage 1 is diagnostic — Stage 1 FAIL keeps the run as a
# warning rather than a hard fail.
set -u

HERE="$(dirname "$0")"
ROOT="$(cd "$HERE/.." && pwd)"
LOG_DIR="$ROOT/experiment_log"
mkdir -p "$LOG_DIR"

source "$HERE/config_v10.sh"

RUNS=1
DO_CLEAN=1
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="${2:-1}"; shift 2 ;;
    --skip-clean) DO_CLEAN=0; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

OK_RUNS=0
WARN_RUNS=0
FAIL_RUNS=0

for n in $(seq 1 "$RUNS"); do
  TS="$(date +%Y%m%d_%H%M%S)"
  echo
  echo "=========================================================="
  echo "v10 regression run $n / $RUNS  -- ts=$TS"
  echo "=========================================================="

  if [ "$DO_CLEAN" -eq 1 ]; then
    bash "$HERE/_clean_leftovers_v10.sh" >"$LOG_DIR/regression_v10_run${n}_${TS}_clean.log" 2>&1
    echo "  cleanup log: $LOG_DIR/regression_v10_run${n}_${TS}_clean.log"
    sleep 30
  fi

  RUN_LOG="$LOG_DIR/regression_v10_run${n}_${TS}.log"
  RUN_JSON="$LOG_DIR/regression_v10_run${n}_${TS}.json"
  STAGE_DIR="$LOG_DIR/regression_v10_run${n}_${TS}_attempts"
  mkdir -p "$STAGE_DIR"

  V5_OUT="$RUN_JSON" V5_LOG_DIR="$STAGE_DIR" python3 "$HERE/regression_v5.py" 2>&1 | tee "$RUN_LOG"
  rc=${PIPESTATUS[0]}
  echo "  regression_v5.py exit=$rc"
  echo "  result json: $RUN_JSON"

  pass_total=$(python3 - "$RUN_JSON" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    keys = ["stage_0", "stage_2", "stage_4", "stage_5", "stage_6"]
    statuses = [d.get(k, {}).get("status") for k in keys]
    s1 = d.get("stage_1", {}).get("status")
    if all(s == "PASS" for s in statuses):
        if s1 == "PASS":
            print("PASS")
        else:
            print("WARN")
    else:
        print("FAIL")
except Exception as e:
    print("FAIL")
PY
)
  echo "  verdict: $pass_total"

  case "$pass_total" in
    PASS) OK_RUNS=$((OK_RUNS+1)) ;;
    WARN) OK_RUNS=$((OK_RUNS+1)); WARN_RUNS=$((WARN_RUNS+1)) ;;
    *)    FAIL_RUNS=$((FAIL_RUNS+1)) ;;
  esac
done

echo
echo "=========================================================="
echo "v10 regression summary: $OK_RUNS/$RUNS pass (warn=$WARN_RUNS, fail=$FAIL_RUNS)"
echo "=========================================================="

[ "$FAIL_RUNS" -eq 0 ]
