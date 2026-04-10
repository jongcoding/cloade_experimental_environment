---
name: harness-loop
description: >-
  싱글 에이전트 하네스 루프. 간단한 작업이나 단일 Stage 작업 시 사용.
  멀티에이전트 조율이 필요한 경우 /orchestrate를 대신 사용할 것.
  Use for simple single-stage work. For multi-stage or parallel work, use /orchestrate instead.
argument-hint: "[시나리오 코드네임]"
disable-model-invocation: true
allowed-tools: Bash(terraform *) Bash(aws *) Bash(bash validation/*) Bash(kubectl *)
---

# 하네스 루프 세션 (싱글 에이전트 모드)

> **참고**: 이 스킬은 싱글 에이전트로 동작한다.
> 복수 Stage 추가, 병렬 작업, 회귀 실패 대응 등 복잡한 작업은 `/orchestrate`를 사용해라.
> `/orchestrate`는 전문 서브에이전트(Terraform Engineer, Attack Executor, Failure Analyst 등)를 스폰해서 병렬로 작업한다.

시나리오: $ARGUMENTS
AWS 계정: [계정 ID]
리전: us-east-1

## 현재 하네스 상태

[harness_state.md 내용 붙여넣기 -- 없으면 아래 양식 사용]

| Stage | Terraform | 단독 검증 | 연결 검증 | 회귀 검증 |
|-------|-----------|-----------|-----------|-----------|
| 0     | [상태]    | [상태]    | -         | [상태]    |
| 1     | [상태]    | [상태]    | [상태]    | [상태]    |

알려진 이슈: [있으면 기록]

## 이번 세션 목표

아래 중 해당하는 것 선택:

### A. 새 Stage 추가
- 추가할 Stage: Stage [N]
- 공격 기법: [기법]
- 이전 Stage에서 넘어오는 것: [자격증명/정보/접근]

### B. 연결 문제 해결
- 깨진 연결: Stage [N-1] -> Stage [N]
- 증상: [에러 메시지]

### C. 전체 회귀 검증
- 범위: Stage 0 -> Stage [N]

### D. 미끼 경로 추가/검증
- 미끼 위치: Stage [N] 부근

---

## 작업 규칙 (매 세션 반드시 준수)

**규칙 1**: Terraform을 리소스 1-2개 단위로 추가 -> apply -> 공격 테스트

**규칙 2**: 새 Stage 추가 시 반드시 순서대로:
  1. 단독 검증: 이 Stage만 공격 가능한가?
  2. 연결 검증: 이전 Stage 결과물로 진입 가능한가?
  3. 회귀 검증: Stage 0부터 전체가 여전히 작동하는가?

**규칙 3**: 매 검증 결과를 구조화해서 기록

**규칙 4**: 실패 시 에러 전문 기록 -> 원인 분류(Terraform/IAM/네트워크/타이밍/명령어) -> 수정 -> 같은 검증 재실행

**규칙 5**: 수동 검증 성공 즉시 `validation/test_stage_N.sh` 스크립트 생성

---

## 세션 시작 시 할 것

1. `cd terraform/ && terraform plan` (드리프트 확인)
2. 이전 인프라 살아있으면 바로 이어서 작업
3. destroy 상태면 `terraform apply -auto-approve` 후 기존 검증 스크립트로 baseline 확인

## 컨텍스트 관리 (긴 세션 필수)

1. **컨텍스트 60% 도달 시** `/compact`를 보존 지침과 함께 실행:
   ```
   /compact Keep: 시나리오 $ARGUMENTS의 공격 체인 구조, harness_state 현재 상태(Stage N까지 검증됨), 이번 세션 발견사항, 현재 작업 중인 Stage와 에러, 다음 단계
   ```
2. **중요 진전마다 harness_state.md 중간 저장** -- 세션 끝까지 기다리지 마라
3. **검증 성공 즉시 스크립트화** -- 컨텍스트를 잃어도 `validation/` 스크립트로 재현 가능

## 세션 종료 시 할 것

1. harness_state.md 최종 업데이트
2. 이번 세션의 발견/변경 기록
3. 다음 세션에서 할 것 명시
4. 비용 확인: `aws ce get-cost-and-usage`
5. 선택: terraform destroy (비용 절감) 또는 유지

---

시작하자. 현재 하네스 상태를 보고 이번 세션의 작업을 진행해.
검증은 반드시 단독 -> 연결 -> 회귀 순서로.
