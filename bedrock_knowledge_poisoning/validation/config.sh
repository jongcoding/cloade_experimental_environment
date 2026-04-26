#!/bin/bash
# Load scenario configuration from terraform outputs
# Source this file at the top of every validation script:
#   source "$(dirname "$0")/config.sh"

set -e

TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform not found"
    exit 1
fi

if [ ! -f "$TF_DIR/terraform.tfstate" ]; then
    echo "ERROR: No terraform state found. Run 'terraform apply' first."
    exit 1
fi

# Load all outputs dynamically
eval "$(cd "$TF_DIR" && terraform output -json 2>/dev/null | python3 -c '
import json, sys
o = json.load(sys.stdin)
for k, v in o.items():
    val = str(v.get("value", ""))
    # Shell-safe export
    print(f"export TF_{k.upper()}=\"{val}\"")
')"

# Convenience aliases
export API_URL="${TF_API_GATEWAY_URL}"
export API_ASK="${TF_API_ASK_ENDPOINT}"
export COGNITO_POOL_ID="${TF_COGNITO_USER_POOL_ID}"
export COGNITO_CLIENT_ID="${TF_COGNITO_CLIENT_ID}"
export AGENT_ID="${TF_BEDROCK_AGENT_ID}"
export KB_ID="${TF_KNOWLEDGE_BASE_ID}"
export DS_ID="${TF_DATA_SOURCE_ID}"
export KB_BUCKET="${TF_KB_DATA_BUCKET}"
export ADMIN_ROLE_ARN="${TF_ADMIN_ROLE_ARN}"
export FLAG_BUCKET="${TF_FLAG_BUCKET}"
export SCENARIO_ID="${TF_SCENARIO_ID}"
export SSM_CONFIG="${TF_SSM_KB_SYNC_CONFIG_PATH}"
export SSM_ADMIN="${TF_SSM_ADMIN_CREDENTIALS_PATH}"
export REGION="${TF_REGION}"

echo "=== Config loaded: scenario_id=${SCENARIO_ID} ==="
