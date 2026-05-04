#!/usr/bin/env bash
# Connection 0->1 (v11): post-Stage-0 IdToken still allows the attacker to
# fetch the SPA bundle and pull AWS_CONFIG. (Trivial: SPA is on a public
# website endpoint, no auth needed; this codifies the "JWT survives the
# pivot" expectation so future regressions catch a regression where the
# SPA gets hardened.)
set -e
HERE="$(dirname "$0")"
bash "$HERE/test_stage_0_v11.sh" >/dev/null
bash "$HERE/test_stage_1_v11.sh"
echo "PASS: connection 0->1 (Cognito JWT in hand, SPA enumerated)"
