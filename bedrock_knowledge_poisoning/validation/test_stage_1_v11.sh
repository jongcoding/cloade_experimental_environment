#!/usr/bin/env bash
# Stage 1 (v11): SPA static-asset reconnaissance.
# Fetch web_ui_url HTML, grep AWS_CONFIG block for IDENTITY_POOL_ID + agent IDs.
set -e
HERE="$(dirname "$0")"
source "$HERE/config_v11.sh"

echo "=== Stage 1 (v11): SPA reconnaissance ($WEB_UI_URL) ==="

curl -s "$WEB_UI_URL/" -o /tmp/v11_stage1_index.html
SIZE=$(wc -c < /tmp/v11_stage1_index.html)
echo "[+] fetched index.html bytes=$SIZE"
[ "$SIZE" -gt 2000 ] || { echo "FAIL: SPA index too small"; exit 1; }

grep -E "identityPoolId|userPoolId|agentId|knowledgeBaseId" /tmp/v11_stage1_index.html | head -20

EXTRACTED_IDP=$(grep -oE 'identityPoolId:[[:space:]]*"[^"]+"' /tmp/v11_stage1_index.html | head -1 | grep -oE '"[^"]+"' | tr -d '"')
EXTRACTED_EMP=$(grep -oE 'agentId:[[:space:]]*"[A-Z0-9]+"' /tmp/v11_stage1_index.html | head -1 | grep -oE '"[^"]+"' | tr -d '"')
EXTRACTED_KB=$(grep -oE 'knowledgeBaseId:[[:space:]]*"[A-Z0-9]+"'  /tmp/v11_stage1_index.html | head -1 | grep -oE '"[^"]+"' | tr -d '"')

echo "[+] identityPoolId=$EXTRACTED_IDP"
echo "[+] employeeAgentId=$EXTRACTED_EMP"
echo "[+] knowledgeBaseId=$EXTRACTED_KB"

if [ "$EXTRACTED_IDP" != "$IDENTITY_POOL_ID" ]; then
  echo "FAIL: SPA IDENTITY_POOL_ID mismatch"; exit 1
fi
if [ "$EXTRACTED_EMP" != "$EMPLOYEE_AGENT_ID" ]; then
  echo "FAIL: SPA employeeAgentId mismatch"; exit 1
fi
if [ "$EXTRACTED_KB" != "$KB_ID" ]; then
  echo "FAIL: SPA knowledgeBaseId mismatch"; exit 1
fi

if grep -q 'adminAgent' /tmp/v11_stage1_index.html; then
  echo "[+] adminAgent block leaked in SPA (matches scenario notes)"
else
  echo "[~] adminAgent block NOT leaked in SPA — chain still works via wildcard probing"
fi

echo "PASS: Stage 1 -- SPA exposes Identity Pool + employee agent IDs"
