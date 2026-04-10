# Cloud Attack Lab -- Experimental Environment

AWS 클라우드 환경에서 **Expert 난이도의 다단계 공격 시나리오**를 실험적으로 설계, 구축, 검증하는 프로젝트.

기존 [CloudGoat](https://github.com/RhinoSecurityLabs/cloudgoat)(Medium~Hard)를 넘어서,
**래터럴 무브먼트 + 크레덴셜 탈취 + 권한 상승**이 5단계 이상 체인으로 엮인 시나리오를 만든다.

리서치가 아닌 **실증(empirical verification)** -- 모든 공격 경로는 실제 AWS 환경에서 `terraform apply -> 공격 실행 -> 결과 확인`으로 검증된다.

---

## 아키텍처: 멀티에이전트 하네스 시스템

이 프로젝트는 **멀티에이전트 구조**로 동작한다.
오케스트레이터가 전문 서브에이전트를 스폰해서 Terraform 작성, 공격 실행, 체인 설계, 정찰, 실패 분석을 병렬/순차로 조율한다.

```
                        ┌──────────────────────────────────┐
                        │  Orchestrator (/orchestrate)      │
                        │  - 작업 유형 판단                   │
                        │  - 에이전트 스폰/조율               │
                        │  - harness_state.md 관리           │
                        │  - 컨텍스트/비용 관리               │
                        └──────────┬───────────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
    ┌─────────▼─────────┐ ┌───────▼───────┐ ┌─────────▼─────────┐
    │ Terraform Engineer │ │Attack Executor│ │  Chain Architect   │
    │ - TF 작성/apply    │ │- 공격 실행     │ │ - 체인 설계         │
    │ - destroy/정리     │ │- 3단계 검증    │ │ - 신규성 검증       │
    │ - 에러 수정        │ │- 스크립트 생성  │ │ - 미끼 설계         │
    └───────────────────┘ └───────────────┘ └───────────────────┘
              │                    │
    ┌─────────▼─────────┐ ┌───────▼───────┐
    │   Recon Scout      │ │Failure Analyst│
    │ - 기법 탐색         │ │- 근본 원인 분석│
    │ - 경계 조건 실험    │ │- 우회 경로 제안│
    │ - 미문서화 동작 발견 │ │- 시나리오 활용 │
    └───────────────────┘ └───────────────┘
```

### 오케스트레이터는 직접 실행하지 않는다

`/orchestrate`의 `allowed-tools`에서 `Bash(terraform *)`, `Bash(aws *)` 등을 제거했다.
오케스트레이터는 terraform/aws 명령어를 물리적으로 실행할 수 없으며, **반드시 Agent 도구로 서브에이전트를 스폰**해야 한다.

이 설계로 다음을 보장한다:
- **역할 분리**: 각 에이전트가 자기 전문 영역에 집중
- **병렬화**: 독립 작업은 동시 스폰으로 시간 단축
- **실패 격리**: 특정 에이전트만 재시도, 전체 컨텍스트 보존
- **컨텍스트 효율**: 오케스트레이터는 결과 요약만 보유

### 에이전트 조율 패턴

오케스트레이터는 상황에 따라 6가지 패턴으로 에이전트를 스폰한다:

| 패턴 | 상황 | 에이전트 흐름 |
|------|------|-------------|
| A. Stage 추가 | 새 Stage 구현 | TF Engineer → Executor(단독→연결→회귀) |
| B. 체인 설계 | 시나리오 초안 | Chain Architect ∥ Recon Scout → 패턴 A |
| C. 탐색+추가 | 기법 불확실 | Recon Scout ∥ TF Engineer → 패턴 A |
| D. 회귀 실패 | 긴급 대응 | Failure Analyst → TF Engineer ∥ Executor |
| E. 중간 검증 | Stage 2-3 완성 | Chain Architect ∥ Executor (병렬) |
| F. 최종 완성 | 전체 완료 | Executor(3회) → Chain Architect ∥ Executor |

`→` 순차, `∥` 병렬

---

## 방법론: 하네스 루프

한 조각을 만들 때마다 검증하고 전체를 이을 때마다 다시 검증하는 구조.

```
Stage N Terraform 작성       ← Terraform Engineer
    | terraform apply
    v
Stage N 단독 검증             ← Attack Executor
    | 성공
    v
Stage N-1 -> N 연결 검증      ← Attack Executor
    | 성공
    v
Stage 0 -> N 회귀 검증        ← Attack Executor
    | 성공
    v
Stage N+1로 확장

    * 실패 -> Failure Analyst -> 수정 -> 같은 검증 재실행
    * 전체 완성 후 destroy -> apply -> 전체 공격 x 3회 반복
```

수동 검증이 성공할 때마다 즉시 `validation/test_stage_N.sh`로 스크립트화.
Stage가 쌓일수록 `validation/regression.sh`로 회귀 검증이 자동화된다.

---

## 신규성 검증

시나리오의 차별화는 **웹서칭으로 찾은 기법이 아니라, 실험에서 발견한 문서에 없는 AWS 동작**에서 나온다.

LLM 웹서칭은 할루시네이션/누락이 발생하므로 판정 근거로 사용하지 않는다.

| Phase | 역할 | 판정 근거? |
|-------|------|-----------|
| 1. 내부 DB 비교 | REFERENCE.md의 CloudGoat + 기존 시나리오와 4항목 매트릭스 비교 | **판정 근거** |
| 2. 실험적 발견 | 문서에 없는 AWS 동작, 예상치 못한 경로, 실험 실패 파생 요소 | **차별화 원천** |
| 3. 외부 참고 | CTF/교육/컨퍼런스 웹서칭 | 참고용 (확정 불가) |
| 4. 기법 분리 | 개별 기법 vs 체인 조합 평가 | 보조 |

```
NOVEL 필수 조건 (모두 충족):
  1. Phase 1에서 유사도 ≤1/4
  2. Phase 2에서 실험적 발견 최소 1개 포함

PARTIAL: Phase 1은 통과하나 실험적 발견이 약함
REJECT:  Phase 1에서 유사도 ≥3/4
```

---

## 프로젝트 구조

```
cloade_experimental_environment/
│
├── CLAUDE.md                     # 핵심 원칙 + 멀티에이전트 구조 + 스킬 목록
├── REFERENCE.md                  # 상세 운영 지침, 신규성 DB, 시나리오 아이디어
├── WORKFLOW.md                   # 멀티에이전트 아키텍처 + 하네스 루프 상세
├── harness_state_template.md     # 시나리오별 진행 상태 추적 템플릿
├── compact_preserve_template.md  # /compact 실행 시 보존 지침 (멀티/싱글 분리)
│
├── .claude/
│   ├── settings.json             # 도구 권한 (terraform, aws, kubectl 등)
│   ├── rules/                    # 항상 적용되는 규칙
│   │   ├── harness-loop.md       # 3단계 검증, 스크립트 즉시 생성
│   │   ├── terraform.md          # 태그 필수, 비용 $2/hr 이하, us-east-1
│   │   ├── aws-experiment.md     # --output json, 에러 기록, 실험 형식
│   │   ├── security.md           # 전용 계정, 자격증명 git 금지
│   │   ├── context-management.md # /compact 60% 규칙, 중간 저장
│   │   └── multi-agent.md        # 오케스트레이터 직접 실행 차단 규칙
│   ├── agents/                   # 서브에이전트 프롬프트 템플릿
│   │   ├── terraform-engineer.md # TF 작성/apply/destroy
│   │   ├── attack-executor.md    # 공격 실행 + 3단계 검증
│   │   ├── chain-architect.md    # 체인 설계 + 신규성 검증
│   │   ├── recon-scout.md        # 기법 탐색 + 미문서화 동작 발견
│   │   └── failure-analyst.md    # 실패 근본 원인 분석
│   └── skills/                   # 슬래시 명령어로 호출하는 스킬
│       ├── orchestrate/          # /orchestrate -- 멀티에이전트 진입점
│       ├── harness-loop/         # /harness-loop -- 싱글에이전트 (단순 작업용)
│       ├── chain-design/         # /chain-design -- 공격 체인 초안
│       ├── attack-discovery/     # /attack-discovery -- 기법 실험
│       ├── novel-discovery/      # /novel-discovery -- 새 벡터 탐색
│       ├── failure-analysis/     # /failure-analysis -- 실패 심화 분석
│       └── final-packaging/      # /final-packaging -- 최종 패키징
│
├── [scenario_name]/              # 시나리오 디렉토리 (시나리오마다 생성)
│   ├── terraform/                # Stage별 인프라 (점진적 확장)
│   ├── assets/                   # Lambda 소스, 공격 도구
│   ├── validation/               # 자동 검증 스크립트
│   ├── experiment_log/           # 실험 가설 + 결과
│   ├── solution/                 # (완성 후) 풀이 문서
│   └── harness_state.md          # 현재 진행 상태
│
├── senario/                      # 로컬 참고용 (git 미추적)
│   ├── cloudgoat/                # CloudGoat 원본
│   └── *_writeup.md              # 기존 시나리오 풀이
│
└── prompts/                      # 레거시 프롬프트 (skills/agents에 통합됨)
```

---

## 사용법

### 전제 조건

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 설치
- AWS CLI + 전용 실험 계정 자격증명
- Terraform >= 1.5
- (선택) kubectl (EKS 시나리오용)

### 멀티에이전트 모드 (권장)

```bash
cd cloade_experimental_environment/

# 공격 체인 설계 + 신규성 검증
# → Chain Architect + Recon Scout가 병렬 스폰
/orchestrate [scenario_name] 체인 설계

# Stage 구현/검증
# → Terraform Engineer → Attack Executor 순차 스폰
/orchestrate [scenario_name] Stage 0 구현

# 회귀 실패 대응
# → Failure Analyst → Terraform Engineer 순차 스폰
/orchestrate [scenario_name] Stage 2 회귀 실패 해결

# 최종 완성
# → Attack Executor(3회) → Chain Architect 스폰
/orchestrate [scenario_name] 최종 검증
```

### 싱글에이전트 모드 (단순 작업)

```bash
# 단일 Stage 빠른 작업
/harness-loop [scenario_name]

# 개별 기법 실험
/attack-discovery "Lambda Layer 교체로 환경변수 탈취 가능한지"

# 새 공격 벡터 탐색
/novel-discovery service

# 전체 완성 후 패키징
/final-packaging [scenario_name]
```

### 긴 세션 관리

컨텍스트 60% 도달 시 `/compact`를 보존 지침과 함께 실행.
`compact_preserve_template.md`에 멀티/싱글 모드별 템플릿이 있다.

---

## 난이도 기준

| 요소 | Expert (이 프로젝트의 목표) |
|------|--------------------------|
| 피봇 단계 수 | 5+ |
| AWS 서비스 | 3개 이상 조합 |
| 미끼/데드엔드 | 핵심 경로보다 미끼가 더 매력적 |
| 웹 기술 | Chained Web Vulns |
| 자격증명 형태 | Cross-service Role Chain |
| 문서화 수준 | 문서에 없는 동작 이해 필요 |

---

## 참고

- [CloudGoat (Rhino Security Labs)](https://github.com/RhinoSecurityLabs/cloudgoat) -- 이 프로젝트가 넘어서려는 기존 클라우드 보안 랩
- [flaws.cloud](http://flaws.cloud/) / [flaws2.cloud](http://flaws2.cloud/) -- AWS 보안 학습 사이트
- [IAM Vulnerable (BishopFox)](https://github.com/BishopFox/iam-vulnerable) -- IAM 권한 상승 전문
