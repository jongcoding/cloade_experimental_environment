#!/usr/bin/env bash
# Connection 2->3 (v11): federated creds enable IAM probing (sts ALLOW,
# bedrock-agent management API DENY).
set -e
HERE="$(dirname "$0")"
bash "$HERE/test_stage_0_v11.sh" >/dev/null
bash "$HERE/test_stage_2_v11.sh" >/dev/null
bash "$HERE/test_stage_3_v11.sh"
echo "PASS: connection 2->3 (IAM permission map under federated creds)"
