#!/usr/bin/env bash
# v11 full-chain regression runner.
#
# Usage:
#   bash validation/run_full_chain_v11.sh                # one run
#   bash validation/run_full_chain_v11.sh --runs 3       # three back-to-back
#
# v11 has *no* server-side artefacts to clean between runs (no comments/,
# no archive/qna/, no ingestion). The attacker creates a fresh Cognito
# user per run; old users stay around but are harmless. We don't bother
# deleting them.
#
# Each run produces:
#   experiment_log/regression_v11_run<N>_<TS>.log   (stdout/stderr)
#   experiment_log/regression_v11_run<N>_<TS>.json  (regression_v11.py result)
#   experiment_log/regression_v11_run<N>_<TS>_attempts/stage5_attempts.json
#
# A run is PASS iff every Stage 0..6 reported PASS (Stage 1 + Stage 3 are
# diagnostic; their FAIL counts as WARN, not hard fail).
set -u
HERE="$(dirname "$0")"
ROOT="$(cd "$HERE/.." && pwd)"
LOG_DIR="$ROOT/experiment_log"
mkdir -p "$LOG_DIR"

source "$HERE/config_v11.sh"

RUNS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="${2:-1}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

OK=0
WARN=0
FAIL=0

for n in $(seq 1 "$RUNS"); do
  TS="$(date +%Y%m%d_%H%M%S)"
  echo
  echo "=========================================================="
  echo "v11 regression run $n / $RUNS  -- ts=$TS"
  echo "=========================================================="

  RUN_LOG="$LOG_DIR/regression_v11_run${n}_${TS}.log"
  RUN_JSON="$LOG_DIR/regression_v11_run${n}_${TS}.json"
  ATT_DIR="$LOG_DIR/regression_v11_run${n}_${TS}_attempts"
  mkdir -p "$ATT_DIR"

  V11_OUT="$RUN_JSON" V11_LOG_DIR="$ATT_DIR" \
    python3 "$HERE/regression_v11.py" 2>&1 | tee "$RUN_LOG"
  rc=${PIPESTATUS[0]}
  echo "  regression_v11.py exit=$rc"

  verdict=$(python3 - "$RUN_JSON" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    must_pass = ["stage_0", "stage_2", "stage_4", "stage_5", "stage_6"]
    diag      = ["stage_1", "stage_3"]
    must_ok = all(d.get(k, {}).get("status") == "PASS" for k in must_pass)
    diag_ok = all(d.get(k, {}).get("status") == "PASS" for k in diag)
    if must_ok and diag_ok:
        print("PASS")
    elif must_ok:
        print("WARN")
    else:
        print("FAIL")
except Exception:
    print("FAIL")
PY
)
  echo "  verdict: $verdict"
  case "$verdict" in
    PASS) OK=$((OK+1)) ;;
    WARN) OK=$((OK+1)); WARN=$((WARN+1)) ;;
    *)    FAIL=$((FAIL+1)) ;;
  esac
done

echo
echo "=========================================================="
echo "v11 regression summary: $OK/$RUNS pass (warn=$WARN fail=$FAIL)"
echo "=========================================================="

[ "$FAIL" -eq 0 ]
