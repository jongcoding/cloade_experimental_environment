#!/usr/bin/env bash
# Run all v11 connection tests in order. Each connection script re-creates
# any prerequisites it needs.
set -e
HERE="$(dirname "$0")"
for pair in 0_1 1_2 2_3 3_4 4_5 5_6; do
  echo
  echo "############ CONNECTION ${pair} ############"
  bash "$HERE/test_connection_${pair}_v11.sh"
done
echo
echo "############ ALL CONNECTIONS PASS ############"
