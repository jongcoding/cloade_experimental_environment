#!/usr/bin/env bash
# v11 scenario wiring (terraform output, scenario_id=7ba56bba).
# Source this file before running stage scripts: `source validation/config_v11.sh`.
#
# v11 = "IAM Drift to the Admin Agent". OWASP API1:2023 BOLA cloud variant.
# ADD_COMMENT + ARCHIVE_QNA mechanisms are gone (v10 → v11 cleanup).
# Chain pivots through Cognito Identity Pool federated role whose
# bedrock:InvokeAgent Resource = "agent-alias/*" (wildcard) accidentally
# covers admin_agent's alias too.

export REGION="us-east-1"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

# --- Public endpoints ---
export API_URL="https://qnu3pu0ole.execute-api.us-east-1.amazonaws.com/prod/chat"
export WEB_UI_URL="http://bkp-web-7ba56bba.s3-website-us-east-1.amazonaws.com"

# --- Cognito ---
export USER_POOL_ID="us-east-1_NyJAX3siq"
export CLIENT_ID="a02bp4u9r3fso4rcsbvhp5btn"
export IDENTITY_POOL_ID="us-east-1:e2045515-b65f-48a3-a07c-a230f5c72890"

# --- Bedrock Agents ---
export EMPLOYEE_AGENT_ID="YJ6X9VEA0H"
export EMPLOYEE_AGENT_ALIAS_ID="TSTALIASID"
export ADMIN_AGENT_ID="RSWGJMHQCA"
export ADMIN_AGENT_ALIAS_ID="TSTALIASID"

# --- KB / S3 ---
export KB_ID="DJCZYQH0GS"
export KB_DATA_BUCKET="bkp-kb-data-7ba56bba"

# --- Federated role ARNs (for reference, not needed for invoke) ---
export EMPLOYEE_FED_ROLE_ARN="arn:aws:iam::542551366766:role/atlas_kb_v10-employee-fed-role-7ba56bba"
export UNAUTH_FED_ROLE_ARN="arn:aws:iam::542551366766:role/atlas_kb_v10-unauth-fed-role-7ba56bba"

# --- Validation seed admin (NOT used in v11 attack chain itself; only for
#     decoy verification + parity with v10) ---
export SEED_ADMIN_USER="security-team@atlas.tech"
export SEED_ADMIN_PASS='AdminSeed!2026'

# --- Flag ---
export EXPECTED_FLAG='FLAG{atlas_unreleased_via_invoke_agent_iam_drift}'
export FLAG_KEY='admin-only/atlas-2026-q2-unreleased/gen/web-sql-vault/README.md'

export SCENARIO_ID="7ba56bba"
