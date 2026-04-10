---
name: final-packaging
description: >-
  전체 공격 체인 + 미끼가 3회 회귀 검증 통과한 후 최종 문서 패키징.
  Terraform/공격 코드는 새로 만들지 않고, 풀이 문서/힌트/README만 작성.
  Use only after all stages pass 3 consecutive regression tests.
argument-hint: "[시나리오 코드네임]"
disable-model-invocation: true
---

# 최종 패키징 세션

시나리오: $ARGUMENTS

## 전제 조건 (충족되어야 시작)

- [ ] 전체 체인 3회 연속 회귀 검증 통과
- [ ] validation/ 스크립트로 자동 검증 가능
- [ ] 미끼 경로 검증 완료
- [ ] harness_state.md에서 모든 Stage PASS
- [ ] 신규성 판정 NOVEL 확인

## 패키징할 것

### Step 1: 풀이 문서

`solution/walkthrough.md`: 실험 로그 기반 상세 풀이
- 각 단계 "왜 이 명령어를 실행했나?"
- 실패한 시도도 포함 ("이건 왜 안 됐나?")
- 각 단계의 깨달은 점
- 최종 공격 흐름 다이어그램

`solution/alternative_paths.md`: 대안 풀이 경로

### Step 2: 힌트 시스템

`cheat_sheet.md`: 각 Stage별 5단계 힌트
- Hint 1 (방향): 어디를 봐야 하는지
- Hint 2 (기법): 무엇을 해야 하는지
- Hint 3 (명령어): 어떤 명령어를 써야 하는지
- Hint 4 (정답): 거의 정답 수준
- Hint 5 (풀이): 전체 풀이

### Step 3: README 및 메타데이터

`README.md`: 시나리오 이름, 난이도, 스토리, 시작점, 목표, 예상 비용
`manifest.yml`: 메타데이터 (서비스 목록, 기법 목록, 예상 시간)

## 품질 체크리스트

- [ ] `terraform init && terraform plan` 에러 없음
- [ ] `terraform apply` 3회 반복 에러 없음
- [ ] `validation/regression.sh` 전체 통과
- [ ] `terraform destroy` 잔여 리소스 없음
- [ ] README가 힌트를 포함하지 않음
- [ ] Flag가 마지막 Stage에서만 접근 가능
- [ ] 미끼 경로가 자연스러움
- [ ] 예상 비용이 시간당 $2 이하
