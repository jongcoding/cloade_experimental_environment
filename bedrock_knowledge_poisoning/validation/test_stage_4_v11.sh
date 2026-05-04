#!/usr/bin/env bash
# Stage 4 (v11): confirm bedrock:InvokeAgent allowed on BOTH employee_agent
# and admin_agent aliases under the federated employee role (agent-alias/*
# wildcard IAM drift). Uses bedrock-agent-runtime invoke_agent which is the
# only way to test InvokeAgent permission with action data-plane semantics.
set -e
HERE="$(dirname "$0")"
source "$HERE/config_v11.sh"
[ -f /tmp/v11_stage2_env.sh ] || { echo "FAIL: run stage 2 first"; exit 1; }
source /tmp/v11_stage2_env.sh

echo "=== Stage 4 (v11): InvokeAgent reachability on both agent aliases ==="

probe_invoke () {
  local LABEL="$1" AID="$2" ALIAS="$3"
  echo
  echo "--- probe[$LABEL] agentId=$AID alias=$ALIAS ---"
  python3 - "$AID" "$ALIAS" "$LABEL" <<'PY'
import sys, uuid, boto3, os
aid, alias, label = sys.argv[1], sys.argv[2], sys.argv[3]
br = boto3.client('bedrock-agent-runtime', region_name=os.environ['AWS_REGION'])
try:
    r = br.invoke_agent(agentId=aid, agentAliasId=alias, sessionId=str(uuid.uuid4()),
                        inputText='ping reachability probe', endSession=True)
    out = ''
    for ev in r.get('completion', []):
        ch = ev.get('chunk', {})
        if 'bytes' in ch:
            out += ch['bytes'].decode('utf-8', 'replace')
    print(f'[ok] {label} responded ({len(out)} bytes)')
    sys.exit(0)
except Exception as e:
    print(f'[err] {label} {type(e).__name__}: {str(e)[:300]}')
    sys.exit(2)
PY
}

set +e
probe_invoke EMP "$EMPLOYEE_AGENT_ID" "$EMPLOYEE_AGENT_ALIAS_ID"; RC_EMP=$?
probe_invoke ADM "$ADMIN_AGENT_ID"    "$ADMIN_AGENT_ALIAS_ID";    RC_ADM=$?
set -e

echo
echo "[summary] employee_agent rc=$RC_EMP   admin_agent rc=$RC_ADM"
if [ $RC_EMP -eq 0 ] && [ $RC_ADM -eq 0 ]; then
  echo "PASS: Stage 4 -- agent-alias/* wildcard covers admin_agent (IAM drift confirmed)"
else
  echo "FAIL: at least one agent unreachable. emp=$RC_EMP adm=$RC_ADM"
  exit 1
fi
