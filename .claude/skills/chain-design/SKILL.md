---
name: chain-design
description: >-
  공격 체인 초안 설계. 30분 이내로 빠르게 스케치하고 바로 Stage 0 구현으로 넘어감.
  Use when starting a new scenario and need to sketch the attack chain.
argument-hint: "[시나리오 코드네임]"
disable-model-invocation: true
---

# 공격 체인 초안 설계

> 주의: 이것은 초안 스케치다. 30분 이상 쓰지 마라. 빨리 스케치하고 `/harness-loop`로 넘어가라.

시나리오 코드네임: $ARGUMENTS
목표 난이도: Expert

## 실험으로 검증된 기법 목록

탐색 실험에서 확인된 공격 기법을 정리해:

| # | 기법 | 실험 ID | 필요 권한 | 성공 조건 | 비고 |
|---|------|---------|-----------|-----------|------|
| 1 | [기법명] | [EXP-001] | [IAM 권한] | [조건] | [특이사항] |

## 시나리오 요구사항

- **진입점**: SSRF / RCE / SQL Injection / Auth Bypass 중 택 1
- **최소 피봇 단계**: 5
- **필수 포함**: 래터럴 무브먼트, 크레덴셜 탈취(2종류+), 권한 상승, 네트워크 경계 넘기
- **미끼 경로**: 최소 3개
- **Flag 위치**: 최종 단계에서만 접근 가능

## 해줄 것 (3개만)

**1. 공격 체인 다이어그램**: ASCII art, 각 Stage마다 기법/획득물/연결/미끼 분기점

**2. 불확실한 단계 표시**: 각 Stage에 "실험 검증됨 / 미검증" 표시

**3. 신규성 검증 (필수)**: REFERENCE.md의 기존 시나리오 DB와 비교해서:
- 가장 유사한 기존 시나리오 3개 찾기
- 4가지 비교 항목(진입점/피봇경로/권한상승/최종도달)에서 몇 개가 다른지 판정
- 3개 이상 다르면 NOVEL -> `/harness-loop`로 진행
- 2개 이하면 체인 수정 후 재판정

## 설계 제약

- 시간당 운영 비용 $2 이하
- terraform destroy 한 번으로 완전 정리
- 리전 단일 (us-east-1)

---

초안 완성 후 `/harness-loop`의 첫 세션 변형으로 Stage 0부터 구현/검증을 시작한다.
