#!/usr/bin/env bash
# Atlas Tech v10 -- destroy 전 정리.
#
# Bedrock Agent action group 이 ENABLED 상태로 남아 있으면 terraform destroy
# 가 의존성 순서로 실패한다. employee_agent / admin_agent 양쪽의 모든 action
# group 을 DISABLED 로 돌린 뒤 destroy 를 시도하라.
#
# Agent ID 는 terraform output 에서 동적으로 읽어오므로 시드 값이 박혀있지
# 않다. 매 배포마다 그대로 재사용 가능.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TF_DIR="$(cd "$(dirname "$0")"/terraform && pwd)"

cd "$TF_DIR"

EMPLOYEE_AID=$(terraform output -raw employee_agent_id 2>/dev/null || true)
ADMIN_AID=$(terraform output -raw admin_agent_id 2>/dev/null || true)

if [[ -z "$EMPLOYEE_AID" && -z "$ADMIN_AID" ]]; then
  echo "[disable_ags] terraform output 에서 agent_id 를 읽지 못했다." >&2
  echo "             $TF_DIR 에서 'terraform apply' 가 한 번 이라도 끝났는지 확인." >&2
  exit 1
fi

disable_one_agent() {
  local agent_id="$1"
  local label="$2"

  if [[ -z "$agent_id" ]]; then
    echo "[disable_ags] $label : agent_id 비어 있음, 건너뜀"
    return 0
  fi

  echo "[disable_ags] $label  ($agent_id) action group 열거 ..."
  local groups_json
  groups_json=$(aws bedrock-agent list-agent-action-groups \
    --agent-id "$agent_id" \
    --agent-version DRAFT \
    --region "$REGION" \
    --output json)

  local count
  count=$(echo "$groups_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["actionGroupSummaries"]))')
  echo "[disable_ags]   action groups = $count"

  echo "$groups_json" | python3 -c '
import json, sys
for g in json.load(sys.stdin)["actionGroupSummaries"]:
    print(g["actionGroupId"] + "\t" + g["actionGroupName"] + "\t" + g["actionGroupState"])
' \
  | while IFS=$'\t' read -r ag_id ag_name ag_state; do
      if [[ "$ag_state" == "DISABLED" ]]; then
        echo "[disable_ags]   $ag_name ($ag_id) 이미 DISABLED"
        continue
      fi

      local schema lambda_arn
      schema=$(aws bedrock-agent get-agent-action-group \
        --agent-id "$agent_id" \
        --agent-version DRAFT \
        --action-group-id "$ag_id" \
        --region "$REGION" \
        --query 'agentActionGroup.functionSchema' \
        --output json)
      lambda_arn=$(aws bedrock-agent get-agent-action-group \
        --agent-id "$agent_id" \
        --agent-version DRAFT \
        --action-group-id "$ag_id" \
        --region "$REGION" \
        --query 'agentActionGroup.actionGroupExecutor.lambda' \
        --output text)

      aws bedrock-agent update-agent-action-group \
        --agent-id "$agent_id" \
        --agent-version DRAFT \
        --action-group-id "$ag_id" \
        --action-group-name "$ag_name" \
        --action-group-state DISABLED \
        --action-group-executor "lambda=$lambda_arn" \
        --function-schema "$schema" \
        --region "$REGION" \
        > /dev/null
      echo "[disable_ags]   $ag_name ($ag_id) -> DISABLED"
    done
}

disable_one_agent "$EMPLOYEE_AID" employee_agent
disable_one_agent "$ADMIN_AID"    admin_agent

echo "[disable_ags] done. 이제 'cd terraform && terraform destroy -auto-approve' 실행 가능."
