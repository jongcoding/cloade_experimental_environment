#!/usr/bin/env bash
# v10 scenario wiring (terraform output). source this file before running the
# stage scripts: `source validation/config_v10.sh`.

export REGION="us-east-1"
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

export API_URL="https://mcv8cbuldf.execute-api.us-east-1.amazonaws.com/prod/chat"
export WEB_UI_URL="http://bkp-web-d3826230.s3-website-us-east-1.amazonaws.com"
export USER_POOL_ID="us-east-1_uOup8A1Pz"
export CLIENT_ID="7j67jhhj9lcgo3bktk3pphmd79"
export KB_ID="4OKUXME9AL"
export DS_ID_PUBLIC="UUYDHGOOFY"
export DS_ID_COMMENTS="CUJUBL0VB0"
export DS_ID_ARCHIVE="LJFV6URA5M"
export KB_DATA_BUCKET="bkp-kb-data-d3826230"
export EMPLOYEE_AGENT_ID="QZY86NY4Y9"
export ADMIN_AGENT_ID="NKNAOVW6RV"

export SEED_ADMIN_USER="security-team@atlas.tech"
export SEED_ADMIN_PASS='AdminSeed!2026'

export EXPECTED_FLAG='FLAG{atlas_unreleased_via_metadata_mass_assignment}'
export COMMENT_TARGET_PATH="atlas-2024-q1/web/sql-basic"
export SCENARIO_ID="d3826230"
