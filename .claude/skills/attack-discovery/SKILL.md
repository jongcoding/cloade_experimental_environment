---
name: attack-discovery
description: >-
  개별 공격 기법의 실현 가능성을 빠르게 실험. 하네스 루프에서 특정 기법이 불확실할 때 사용.
  Use when testing a specific AWS attack technique, verifying if an exploit works,
  or exploring a new attack surface before adding it as a stage.
argument-hint: "[실험할 기법 설명]"
disable-model-invocation: true
allowed-tools: Bash(terraform *) Bash(aws *)
---

# 공격 표면 탐색 실험 세션

현재 목표: $ARGUMENTS
리전: us-east-1

## 이전 실험 결과 요약
[이전 세션에서 확인된 사실 -- 없으면 "첫 실험"]

## 각 실험에 대해 해줄 것

실험마다 다음 순서로 진행해:

**Step 1 -- 가설 작성**: "어떤 권한이 있으면 어떤 결과가 나올 것이다"

**Step 2 -- 최소 Terraform**: 가설 검증을 위한 최소 인프라, 태그 필수

**Step 3 -- 배포 & 실행**: terraform apply -> 공격 명령어 실행, 모든 출력 기록

**Step 4 -- 결과 분석**:
- 성공: 최소 필요 권한, 조건, 방어 방법 정리
- 실패: 에러 분석 + 우회 가능성 분석

**Step 5 -- 발견 기록**: AWS 문서에 없는 동작, 예상과 다른 결과

**Step 6 -- 다음 실험 제안**: 이 결과를 바탕으로 다음 실험

## 제약

- 비용 $5 이내
- 실험 후 반드시 terraform destroy

---

실험 완료 후 복귀:
- **멀티에이전트**: `/orchestrate [코드네임] [기법]을 Stage로 구현` (권장)
- **싱글에이전트**: `/harness-loop [코드네임]`

> **팁**: `/orchestrate` 사용 시, 이 실험 결과가 Recon Scout 에이전트 → Terraform Engineer 에이전트로 자동 전달된다.
