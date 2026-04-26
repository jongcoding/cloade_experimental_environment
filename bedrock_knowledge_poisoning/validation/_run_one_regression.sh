#!/bin/bash
# Single regression run: clean leftovers, re-ingest seeds, run chain.
# Usage: _run_one_regression.sh <runN> <ts>
set -e
RUN_TAG=$1
TS=$2
cd /mnt/c/Users/ialleejy/Desktop/cloud/cloade_experimental_environment/bedrock_knowledge_poisoning

echo "=============================================="
echo "=== Regression $RUN_TAG starting ($TS) ==="
echo "=============================================="

bash validation/_clean_leftovers.sh
bash validation/_reingest_seeds.sh

LOG="experiment_log/regression_v9_patch3_${RUN_TAG}_${TS}.log"
OUT="/tmp/regression_v9_patch3_${RUN_TAG}.json"
V4_OUT="$OUT" python3 validation/regression_v4.py 2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}
echo "=== Regression $RUN_TAG exit=$EXIT log=$LOG ==="
