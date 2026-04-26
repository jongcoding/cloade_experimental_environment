#!/usr/bin/env bash
# Verify .metadata.json sidecars across kb_data prefixes carry the expected
# audience field (v10 metadata mass assignment investigation).
#
# Usage:
#   bash validation/_verify_metadata.sh                # quick summary
#   bash validation/_verify_metadata.sh comments       # only comments/
#   bash validation/_verify_metadata.sh archive        # only archive/qna/
#   bash validation/_verify_metadata.sh public         # only public/
#
# Reports per-file (key -> audience) and counts per audience tier.

set -u
HERE="$(dirname "$0")"
source "$HERE/config_v10.sh"

PREFIX_FILTER="${1:-all}"

case "$PREFIX_FILTER" in
  comments) prefixes=("comments/") ;;
  archive)  prefixes=("archive/qna/") ;;
  public)   prefixes=("public/") ;;
  all|*)    prefixes=("public/" "comments/" "archive/qna/") ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

for p in "${prefixes[@]}"; do
  echo "=== prefix: $p ==="
  aws s3api list-objects-v2 \
    --bucket "$KB_DATA_BUCKET" \
    --prefix "$p" \
    --query "Contents[?ends_with(Key, \`.metadata.json\`)].[Key]" \
    --output text \
    --region "$REGION" > "$TMP_DIR/keys.txt"

  total=0
  declare -A counts=()
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    total=$((total+1))
    body="$(aws s3api get-object \
              --bucket "$KB_DATA_BUCKET" \
              --key    "$key" \
              --region "$REGION" \
              "$TMP_DIR/sidecar.json" >/dev/null 2>&1 && cat "$TMP_DIR/sidecar.json")"
    audience="$(printf '%s' "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("metadataAttributes",{}).get("audience","-"))' 2>/dev/null || echo '?')"
    printf '  %-72s audience=%s\n' "$key" "$audience"
    counts[$audience]=$(( ${counts[$audience]:-0} + 1 ))
  done < "$TMP_DIR/keys.txt"

  echo "  --- total .metadata.json under $p: $total ---"
  for a in "${!counts[@]}"; do
    printf '  audience=%-10s %d\n' "$a" "${counts[$a]}"
  done
  echo
  unset counts
done
