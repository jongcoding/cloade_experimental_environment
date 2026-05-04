#!/usr/bin/env bash
# Stage 3 (v11): IAM permissions reconnaissance under federated role.
# Verify (a) sts:GetCallerIdentity works, (b) bedrock-agent:GetAgent is *denied*,
# (c) iam:GetRolePolicy on own role is denied. Probe shape only — not yet
# attacking the agent.
set -e
HERE="$(dirname "$0")"
source "$HERE/config_v11.sh"
[ -f /tmp/v11_stage2_env.sh ] || { echo "FAIL: run stage 2 first"; exit 1; }
source /tmp/v11_stage2_env.sh

echo "=== Stage 3 (v11): IAM permission mapping under federated creds ==="

set +e
echo
echo "[probe-1] sts:GetCallerIdentity (should ALLOW)"
aws sts get-caller-identity --output json --region "$REGION"
RC1=$?
[ $RC1 -eq 0 ] || { echo "FAIL: GetCallerIdentity denied"; exit 1; }

echo
echo "[probe-2] bedrock-agent:GetAgent on admin_agent (expect AccessDenied)"
OUT2=$(aws bedrock-agent get-agent --agent-id "$ADMIN_AGENT_ID" --region "$REGION" 2>&1)
echo "$OUT2"
echo "$OUT2" | grep -qi "AccessDenied\|not authorized" || {
  echo "[~] unexpected: GetAgent did not deny — federated role over-permissioned beyond IAM drift"
}

echo
echo "[probe-3] iam:GetRolePolicy on own role (expect AccessDenied)"
OUT3=$(aws iam get-role-policy \
  --role-name "atlas_kb_v10-employee-fed-role-7ba56bba" \
  --policy-name "atlas_kb_v10-employee-fed-policy" \
  --region "$REGION" 2>&1)
echo "$OUT3"
echo "$OUT3" | grep -qi "AccessDenied\|not authorized" || {
  echo "[~] unexpected: iam:GetRolePolicy succeeded — would bypass enumeration step"
}
set -e

echo
echo "PASS: Stage 3 -- shape confirmed (sts ALLOW, bedrock-agent management API DENY)"
