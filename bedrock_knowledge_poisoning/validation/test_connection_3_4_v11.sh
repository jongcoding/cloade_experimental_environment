#!/usr/bin/env bash
# Connection 3->4 (v11): IAM probing surfaces that bedrock:InvokeAgent is
# allowed; Stage 4 confirms BOTH agent aliases are reachable.
set -e
HERE="$(dirname "$0")"
bash "$HERE/test_stage_0_v11.sh" >/dev/null
bash "$HERE/test_stage_2_v11.sh" >/dev/null
bash "$HERE/test_stage_4_v11.sh"
echo "PASS: connection 3->4 (employee + admin agent both reachable)"
