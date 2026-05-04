#!/usr/bin/env bash
# Stage 6 (v11): parse Stage 5 completion stream for the flag and validate
# format match against EXPECTED_FLAG.
set -e
HERE="$(dirname "$0")"
source "$HERE/config_v11.sh"

[ -f /tmp/v11_stage5_out.txt ] || { echo "FAIL: run stage 5 first"; exit 1; }

echo "=== Stage 6 (v11): flag extraction from admin_agent completion stream ==="

FOUND=$(grep -oE 'FLAG\{atlas[^}]+\}' /tmp/v11_stage5_out.txt | head -1)
echo "[+] extracted: $FOUND"
echo "[+] expected:  $EXPECTED_FLAG"

[ "$FOUND" = "$EXPECTED_FLAG" ] || { echo "FAIL: flag mismatch"; exit 1; }
echo "PASS: Stage 6 -- recovered $FOUND"
