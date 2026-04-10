# Cloud Attack Lab -- Experimental Environment

AWS 클라우드 다단계 공격 시나리오를 실험적으로 설계/구축/검증하는 프로젝트.
연구(research)가 아닌 실증(empirical verification)에 초점.

## 미션

기존 CloudGoat 수준을 넘어서, **다단계 래터럴 무브먼트 + 크레덴셜 탈취 + 권한 상승** 체인을 가진
Expert 난이도 공격 시나리오를 설계하고, 실제 AWS 환경에서 실험으로 검증한 뒤 하네스로 패키징한다.

## 핵심 원칙

1. 모든 공격 경로는 `terraform apply -> 공격 실행 -> 결과 확인` 실험 루프를 거쳐야 한다
2. 실패에서 배워라 -- 실패 원인이 시나리오의 난이도 요소가 된다
3. 단일 기법이 아닌 체인을 만들어라 -- 최소 3단계 이상 피봇
4. 방어자 관점을 포함하라 -- 각 단계에 대응하는 탐지/방어 메커니즘
5. 기존 시나리오와 중복되지 않는지 검증하라 -- 체인 수준에서 차별화 입증 필수

## 하네스 루프 (작업 방식)

선형이 아니라 반복이다. 매 Stage 추가 시 3단계 검증 필수:

1. **단독 검증**: 이 Stage의 공격이 기술적으로 가능한가?
2. **연결 검증**: 이전 Stage의 출력물로 이 Stage에 진입 가능한가?
3. **회귀 검증**: Stage 0부터 여기까지 전체가 여전히 작동하는가?

하나라도 실패하면 다음 Stage로 넘어가지 않는다.

상세 워크플로우: @WORKFLOW.md

## 주요 스킬 (슬래시 명령어)

| 명령어 | 용도 |
|--------|------|
| `/harness-loop` | 핵심 작업 세션. 모든 Stage 구현/검증의 중심 |
| `/chain-design` | 공격 체인 초안 설계 (30분 이내) |
| `/attack-discovery` | 개별 기법의 실현 가능성 실험 |
| `/novel-discovery` | 기존에 없는 새 공격 벡터 탐색 |
| `/failure-analysis` | 검증 실패 원인 심화 분석 |
| `/final-packaging` | 3회 회귀 통과 후 문서/힌트 작성 |

## 컨텍스트 관리

긴 세션에서 컨텍스트가 밀리는 것을 방지하기 위한 3단계 전략:

1. **`/compact` 선제 실행**: 컨텍스트 60% 도달 시 보존 지침과 함께 실행
2. **harness_state.md 중간 저장**: 세션 끝만이 아니라 중요 진전마다 업데이트
3. **검증 스크립트 즉시 생성**: 성공한 검증은 스크립트로 남겨서 컨텍스트 상실에도 재현 가능

`/compact` 실행 시 반드시 보존할 것:
- 현재 시나리오 코드네임 + 공격 체인 구조
- harness_state 현재 상태 (어디까지 검증됐는지)
- 이번 세션의 발견/미해결 이슈
- 현재 작업 중인 Stage + 에러 상황

## 하네스 상태 추적

매 세션 끝에 (+ 중간 진전 시) `harness_state.md`를 업데이트. 템플릿: @harness_state_template.md

## 타겟 난이도: Expert

- 5단계 이상의 피봇
- 3개 이상의 미끼 경로
- 최소 1개의 "문서에 명시되지 않은 AWS 동작" 활용
- 웹 기술 + 클라우드 지식의 복합적 요구

## 체인 설계 템플릿

```
Stage 0 [진입점]: 웹 취약점 -> 초기 자격증명/접근 획득
Stage 1 [정찰]: IAM/서비스 열거 -> 공격 벡터 식별
Stage 2 [래터럴]: 다른 서비스/역할/계정으로 이동
Stage 3 [크레덴셜]: 더 높은 권한의 자격증명 획득
Stage 4 [권한 상승]: 최종 목표 접근 권한 확보
Stage 5 [Flag]: Flag 획득
```

## 신규성 검증

**내부 + 외부** 소스와 비교해서 체인 수준에서 차별화 확인.

### 검증 범위 (5단계)

| Phase | 비교 대상 | 방법 |
|-------|----------|------|
| 1. 내부 비교 | CloudGoat DB + 기존 풀이 시나리오 | 4항목 매트릭스 비교 |
| 2. CTF 대회 | Cloud Village, WIZ CTF, HackTheBox, flAWS | Writeup 검색 + 웹 조사 |
| 3. 교육 플랫폼 | AWSGoat, CloudFoxable, IAM Vulnerable, Thunder CTF, Sadcloud | GitHub/공식 문서 확인 |
| 4. 컨퍼런스 | fwd:cloudsec, DEFCON/BlackHat, Rhino Security, Hacking The Cloud | 발표 목록 + 블로그 검색 |
| 5. 기법 분리 평가 | 개별 기법 vs 체인 조합 | 기법은 KNOWN이어도 체인이 NOVEL이면 OK |

### 검증 시점

| 시점 | 범위 |
|------|------|
| 초안 설계 시 | Phase 1 (내부) 필수, Phase 2-4 간략 검색 |
| Stage 2-3 완성 시 | Phase 1-4 전체 실행 |
| 최종 완성 후 | Phase 1-5 전체 + 보고서 작성 (`experiment_log/novelty_assessment.md`) |

### 판정 기준

```
NOVEL:   모든 비교 대상과 유사도 ≤1/4, 체인 조합 전례 없음
PARTIAL: 2-3개 항목 동일하나 나머지 차별화
REJECT:  유사도 3/4 이상인 기존 시나리오 존재
```

상세 비교 DB: @REFERENCE.md (신규성 검증 섹션)

## 참고 자료

- 상세 운영 지침: @REFERENCE.md
- 실험 우선순위/아이디어: @REFERENCE.md (실험 우선순위 섹션)
- 기존 풀이 시나리오: senario/ (로컬 참고용, git 미추적)
