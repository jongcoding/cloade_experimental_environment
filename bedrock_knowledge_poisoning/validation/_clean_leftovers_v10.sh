#!/usr/bin/env bash
# Between regression runs we need to delete attacker-generated artifacts so
# each loop starts from the seeded state:
#
#   * comments/ entries authored by atlas-attacker-* / unknown_*  (and their
#     .metadata.json sidecars)
#   * archive/qna/ entries written during the previous run (everything except
#     the seed two — which always have keys 2025-12-10-* and 2026-01-18-*)
#   * cognito users matching attacker-v10-*@atlas.example
#
# The seeded comments/atlas-2024-q1/... files (dev1-... ~ dev9-...) are kept
# untouched; we only delete attacker-* / unknown_* / security-team_* prefixes.
set -u

HERE="$(dirname "$0")"
source "$HERE/config_v10.sh"

echo "=== v10 clean-leftovers under bucket=$KB_DATA_BUCKET ==="

# -------------------------------------------------------------------
# 1. Delete attacker comments under comments/
# -------------------------------------------------------------------
echo "--- attacker comments ---"
aws s3api list-objects-v2 \
  --bucket "$KB_DATA_BUCKET" \
  --prefix "comments/" \
  --region "$REGION" \
  --query 'Contents[].Key' \
  --output text 2>/dev/null \
| tr '\t' '\n' \
| while IFS= read -r key; do
    [ -z "$key" ] && continue
    base="$(basename "$key")"
    case "$base" in
      attacker-v10-*|attacker-v10-*.metadata.json|unknown*|security-team*|*-attacker*-*)
        echo "  delete $key"
        aws s3 rm "s3://$KB_DATA_BUCKET/$key" --region "$REGION" >/dev/null
        ;;
    esac
  done

# -------------------------------------------------------------------
# 2. Delete archive/qna/ entries except the two seeded files
# -------------------------------------------------------------------
echo "--- archive/qna/ run-time entries ---"
aws s3api list-objects-v2 \
  --bucket "$KB_DATA_BUCKET" \
  --prefix "archive/qna/" \
  --region "$REGION" \
  --query 'Contents[].Key' \
  --output text 2>/dev/null \
| tr '\t' '\n' \
| while IFS= read -r key; do
    [ -z "$key" ] && continue
    case "$key" in
      archive/qna/2025-12-10-a1b2c3d4.md|archive/qna/2025-12-10-a1b2c3d4.md.metadata.json) ;;
      archive/qna/2026-01-18-b5c6d7e8.md|archive/qna/2026-01-18-b5c6d7e8.md.metadata.json) ;;
      *)
        echo "  delete $key"
        aws s3 rm "s3://$KB_DATA_BUCKET/$key" --region "$REGION" >/dev/null
        ;;
    esac
  done

# -------------------------------------------------------------------
# 3. Trigger ingestion on comments + archive so deletions propagate
# -------------------------------------------------------------------
echo "--- re-ingest comments + archive ---"
for ds in "$DS_ID_COMMENTS" "$DS_ID_ARCHIVE"; do
  aws bedrock-agent start-ingestion-job \
    --knowledge-base-id "$KB_ID" \
    --data-source-id    "$ds" \
    --region "$REGION" \
    --output json 2>&1 | head -10
done

# -------------------------------------------------------------------
# 4. Delete attacker Cognito users
# -------------------------------------------------------------------
echo "--- attacker cognito users ---"
aws cognito-idp list-users \
  --user-pool-id "$USER_POOL_ID" \
  --region "$REGION" \
  --filter 'email ^= "attacker-v10-"' \
  --output text \
  --query 'Users[].Username' 2>/dev/null \
| tr '\t' '\n' \
| while IFS= read -r u; do
    [ -z "$u" ] && continue
    echo "  delete $u"
    aws cognito-idp admin-delete-user \
      --user-pool-id "$USER_POOL_ID" \
      --username     "$u" \
      --region "$REGION" >/dev/null
  done

echo "=== clean-leftovers complete ==="
