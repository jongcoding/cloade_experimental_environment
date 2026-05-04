#!/usr/bin/env bash
# Connection 5->6 (v11): Stage 5 completion stream contains the flag in
# plaintext; Stage 6 extracts and verifies.
set -e
HERE="$(dirname "$0")"
bash "$HERE/test_stage_0_v11.sh" >/dev/null
bash "$HERE/test_stage_2_v11.sh" >/dev/null
bash "$HERE/test_stage_5_v11.sh" >/dev/null
bash "$HERE/test_stage_6_v11.sh"
echo "PASS: connection 5->6 (flag recovered from completion stream)"
