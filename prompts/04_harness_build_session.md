# 보조 프롬프트 -- 최종 패키징 세션

> 사용 시점: 전체 공격 체인 + 미끼가 3회 회귀 검증을 통과한 후.
> 이 세션에서는 Terraform/공격 코드를 새로 만들지 않는다.
> 하네스 루프에서 이미 만들어진 것들을 정리하고, 풀이 문서/힌트/README만 작성한다.

---

```
## 최종 패키징 세션

시나리오: [코드네임]
검증 완료된 공격 체인:
```
[Stage 0] 웹 취약점 -> [Stage 1] 정찰 -> [Stage 2] 래터럴 -> [Stage 3] 크레덴셜 -> [Stage 4] 권한상승 -> [Stage 5] Flag
```

### 전제 조건 (이것이 충족되어야 이 세션을 시작한다)

- [ ] 전체 체인이 3회 연속 회귀 검증 통과
- [ ] validation/ 스크립트로 자동 검증 가능
- [ ] 미끼 경로 검증 완료
- [ ] harness_state.md에서 모든 Stage가 PASS

### 패키징할 것

Terraform, validation 스크립트, 공격 코드는 이미 하네스 루프에서 만들어져 있다.
이 세션에서는 아래 문서만 작성한다.

#### Step 1: 풀이 문서

```
solution/
├── walkthrough.md        # 상세 풀이 (실험 로그 기반)
├── attack_scripts/       # 각 Stage 자동화 스크립트
│   ├── stage0_exploit.py
│   ├── stage1_recon.sh
│   ├── stage2_lateral.sh
│   ├── stage3_cred_steal.sh
│   ├── stage4_privesc.sh
│   └── stage5_get_flag.sh
└── alternative_paths.md  # 대안 풀이 경로 (있다면)
```

walkthrough.md 형식:
- 각 단계마다 "왜 이 명령어를 실행했나?" 설명
- 실패한 시도도 포함 ("이건 왜 안 됐나?")
- 각 단계의 "깨달은 점"
- 최종 공격 흐름 다이어그램

#### Step 2: 힌트 시스템

```
cheat_sheet.md
```

5단계 힌트:
- Hint 1 (방향): "어디를 봐야 하는지" 수준
- Hint 2 (기법): "무엇을 해야 하는지" 수준
- Hint 3 (명령어): "어떤 명령어를 써야 하는지" 수준
- Hint 4 (정답): 거의 정답 수준
- Hint 5 (풀이): 전체 풀이

각 Stage별로 5단계 힌트를 제공.

#### Step 3: README 및 메타데이터

```
README.md     # 시나리오 소개
manifest.yml  # 메타데이터
```

README 내용:
- 시나리오 이름, 난이도, 예상 소요시간
- 시나리오 스토리 (왜 이런 환경이 존재하는지)
- 시작점 (어떤 정보가 주어지는지)
- 목표 (무엇을 찾아야 하는지)
- 전제 조건 (필요한 도구)
- 예상 비용

manifest.yml:
```yaml
scenario_name: [name]
difficulty: Expert
size: Large
estimated_time: 3-5 hours
estimated_cost_per_hour: $1.50
aws_services:
  - [서비스 목록]
attack_techniques:
  - lateral_movement
  - credential_theft
  - privilege_escalation
  - [기타]
cve_references: []  # 실제 CVE 기반이면 기록
author: [이름]
version: "1.0"
```

### 품질 체크리스트

구현이 끝나면 다음을 확인해줘:

- [ ] `terraform init && terraform plan` 에러 없음
- [ ] `terraform apply` 에러 없음 (3회 반복 테스트)
- [ ] `validation/regression.sh` 전체 통과
- [ ] `terraform destroy` 잔여 리소스 없음
- [ ] README가 시작점 외에 힌트를 포함하지 않음
- [ ] outputs.tf가 풀이에 필요한 최소 정보만 출력
- [ ] Flag가 마지막 Stage에서만 접근 가능
- [ ] 미끼 경로가 자연스러움
- [ ] 예상 비용이 시간당 $2 이하
```
