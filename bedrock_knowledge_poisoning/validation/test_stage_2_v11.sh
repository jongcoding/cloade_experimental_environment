#!/usr/bin/env bash
# Stage 2 (v11): cognito-identity:GetId + GetCredentialsForIdentity.
# Exchange employee IdToken for federated AWS temp creds (atlas_employee_federated).
# Output: /tmp/v11_stage2_creds.json with AccessKeyId/SecretKey/SessionToken.
set -e
HERE="$(dirname "$0")"
source "$HERE/config_v11.sh"

[ -f /tmp/v11_stage0_idtoken.txt ] || { echo "FAIL: run stage 0 first"; exit 1; }
ID_TOKEN=$(cat /tmp/v11_stage0_idtoken.txt)

echo "=== Stage 2 (v11): Identity Pool credential exchange ==="

PROVIDER="cognito-idp.${REGION}.amazonaws.com/${USER_POOL_ID}"

aws cognito-identity get-id \
  --identity-pool-id "$IDENTITY_POOL_ID" \
  --logins "${PROVIDER}=${ID_TOKEN}" \
  --region "$REGION" --output json > /tmp/v11_stage2_getid.json
IDENTITY_ID=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage2_getid.json'))['IdentityId'])")
echo "[+] IdentityId=$IDENTITY_ID"

aws cognito-identity get-credentials-for-identity \
  --identity-id "$IDENTITY_ID" \
  --logins "${PROVIDER}=${ID_TOKEN}" \
  --region "$REGION" --output json > /tmp/v11_stage2_creds.json

AKI=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage2_creds.json'))['Credentials']['AccessKeyId'])")
SAK=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage2_creds.json'))['Credentials']['SecretKey'])")
TOK=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage2_creds.json'))['Credentials']['SessionToken'])")
echo "[+] AccessKeyId=$AKI (federated temp creds acquired)"

cat > /tmp/v11_stage2_env.sh <<EOF
export AWS_ACCESS_KEY_ID="$AKI"
export AWS_SECRET_ACCESS_KEY="$SAK"
export AWS_SESSION_TOKEN="$TOK"
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"
EOF
echo "[+] env saved to /tmp/v11_stage2_env.sh"

WHO=$(AWS_ACCESS_KEY_ID="$AKI" AWS_SECRET_ACCESS_KEY="$SAK" AWS_SESSION_TOKEN="$TOK" \
  aws sts get-caller-identity --output json --region "$REGION")
echo "$WHO"
ARN=$(echo "$WHO" | python3 -c "import json,sys;print(json.load(sys.stdin)['Arn'])")
case "$ARN" in
  *atlas*employee-fed*) echo "PASS: Stage 2 -- assumed federated employee role";;
  *) echo "FAIL: unexpected ARN $ARN"; exit 1;;
esac
