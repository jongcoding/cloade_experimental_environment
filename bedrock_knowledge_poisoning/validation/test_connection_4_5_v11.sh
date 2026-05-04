#!/usr/bin/env bash
# Connection 4->5 (v11): given InvokeAgent reachability on admin_agent,
# Stage 5 succeeds at coercing GET_ATLAS_REFERENCE via injected
# sessionAttributes.user_role=admin.
set -e
HERE="$(dirname "$0")"
bash "$HERE/test_stage_0_v11.sh" >/dev/null
bash "$HERE/test_stage_2_v11.sh" >/dev/null
bash "$HERE/test_stage_5_v11.sh"
echo "PASS: connection 4->5 (admin_ops gate bypassed via sessionAttributes injection)"
