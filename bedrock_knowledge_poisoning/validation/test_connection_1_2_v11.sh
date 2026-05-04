#!/usr/bin/env bash
# Connection 1->2 (v11): SPA-derived IDENTITY_POOL_ID + Stage-0 IdToken
# successfully exchange for atlas_employee_federated AWS temp credentials.
set -e
HERE="$(dirname "$0")"
bash "$HERE/test_stage_0_v11.sh" >/dev/null
bash "$HERE/test_stage_1_v11.sh" >/dev/null
bash "$HERE/test_stage_2_v11.sh"
echo "PASS: connection 1->2 (IdentityPool exchange yields federated creds)"
