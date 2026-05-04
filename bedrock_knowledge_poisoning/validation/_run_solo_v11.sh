#!/usr/bin/env bash
# Run all v11 solo stage tests in order. Used by the harness orchestrator
# to invoke the chain through PowerShell wsl without quoting issues.
set -e
HERE="$(dirname "$0")"
for i in 0 1 2 3 4 5 6; do
  echo
  echo "############ STAGE $i SOLO ############"
  bash "$HERE/test_stage_${i}_v11.sh"
done
echo
echo "############ ALL STAGES PASS ############"
