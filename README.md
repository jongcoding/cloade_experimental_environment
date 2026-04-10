# Cloud Attack Lab -- Experimental Environment

AWS 클라우드 환경에서 **Expert 난이도의 다단계 공격 시나리오**를 실험적으로 설계, 구축, 검증하는 프로젝트.

기존 [CloudGoat](https://github.com/RhinoSecurityLabs/cloudgoat)(Medium~Hard)를 넘어서,
**래터럴 무브먼트 + 크레덴셜 탈취 + 권한 상승**이 5단계 이상 체인으로 엮인 시나리오를 만든다.

리서치가 아닌 **실증(empirical verification)** -- 모든 공격 경로는 실제 AWS 환경에서 `terraform apply -> 공격 실행 -> 결과 확인`으로 검증된다.

---

## 시나리오

| 코드네임 | 난이도 | 진입점 | 서비스 | 상태 |
|----------|--------|--------|--------|------|
| [edge_phantom](edge_phantom/) | Expert | CSS Injection via CloudFront CDN | CloudFront, S3, API Gateway, Lambda@Edge, IAM, SSM, DynamoDB | Stage 0 검증 완료 |

### edge_phantom -- CloudFront CDN CSS Injection Chain Attack

```
Stage 0: CSS Injection on CloudFront webapp
         -> Admin 페이지의 data-api-key 속성값 탈취
Stage 1: API Gateway 인증 엔드포인트 열거
         -> S3 origin 버킷명 + Lambda@Edge 정보 발견
Stage 2: S3 Bucket Policy 우회 -> Lambda 배포 패키지 접근
         -> Lambda 소스코드에서 Role ARN + SSM 경로 발견
Stage 3: Lambda@Edge Role -> SSM Parameter Store
         -> 관리자급 IAM 자격증명 탈취
Stage 4: iam:CreatePolicyVersion -> Admin 권한 확보
Stage 5: DynamoDB에서 Flag 획득
```

기존 CloudGoat 어디에도 없는 **CSS Injection 진입점 + CDN 피봇 경로 + Lambda@Edge 활용** 조합. 신규성 판정 NOVEL.

---

## 방법론: 하네스 루프

"설계 -> 구현 -> 마지막에 검증"이 아니라, **한 조각을 만들 때마다 검증하고 전체를 이을 때마다 다시 검증**하는 구조.

```
Stage N Terraform 작성
    | terraform apply
    v
Stage N 단독 검증 -- "이 Stage만 공격 가능한가?"
    | 성공
    v
Stage N-1 -> N 연결 검증 -- "이전 결과물로 진입 가능한가?"
    | 성공
    v
Stage 0 -> N 회귀 검증 -- "처음부터 끝까지 여전히 작동하는가?"
    | 성공
    v
Stage N+1로 확장

    * 어디서든 실패하면 -> 원인 분석 -> 수정 -> 같은 검증 재실행
    * 전체 완성 후 destroy -> apply -> 전체 공격 x 3회 반복
```

수동 검증이 성공할 때마다 즉시 `validation/test_stage_N.sh`로 스크립트화.
Stage가 쌓일수록 `validation/regression.sh`로 회귀 검증이 자동화된다.

---

## 프로젝트 구조

```
cloade_experimental_environment/
|
|-- CLAUDE.md                     # Claude Code 프로젝트 메모리 (핵심 원칙 + 스킬 목록)
|-- REFERENCE.md                  # 상세 운영 지침, 신규성 DB, 시나리오 아이디어
|-- WORKFLOW.md                   # 하네스 루프 상세 다이어그램 + 세션 흐름
|-- harness_state_template.md     # 시나리오별 진행 상태 추적 템플릿
|-- compact_preserve_template.md  # /compact 실행 시 보존 지침 템플릿
|
|-- .claude/
|   |-- settings.json             # 도구 권한 (terraform, aws, kubectl 등)
|   |-- rules/                    # 항상 적용되는 규칙
|   |   |-- harness-loop.md       # 3단계 검증, 스크립트 즉시 생성
|   |   |-- terraform.md          # 태그 필수, 비용 $2/hr 이하, us-east-1
|   |   |-- aws-experiment.md     # --output json, 에러 기록, 실험 형식
|   |   |-- security.md           # 전용 계정, 자격증명 git 금지
|   |   |-- context-management.md # /compact 60% 규칙, 중간 저장
|   |-- skills/                   # 슬래시 명령어로 호출하는 스킬
|       |-- harness-loop/         # /harness-loop -- 핵심 작업 세션
|       |-- chain-design/         # /chain-design -- 공격 체인 초안
|       |-- attack-discovery/     # /attack-discovery -- 기법 실험
|       |-- novel-discovery/      # /novel-discovery -- 새 벡터 탐색
|       |-- failure-analysis/     # /failure-analysis -- 실패 심화 분석
|       |-- final-packaging/      # /final-packaging -- 최종 패키징
|
|-- edge_phantom/                 # [시나리오] CSS Injection CDN Chain
|   |-- terraform/                # Stage별 인프라 (점진적 확장)
|   |-- assets/                   # Lambda 소스, 공격 도구
|   |-- validation/               # 자동 검증 스크립트
|   |-- experiment_log/           # 실험 가설 + 결과
|   |-- solution/                 # (완성 후) 풀이 문서
|   |-- harness_state.md          # 현재 진행 상태
|   |-- README.md                 # 시나리오 개요
|
|-- senario/                      # 로컬 참고용 (git 미추적)
|   |-- cloudgoat/                # CloudGoat 원본 — .gitignore로 제외
|   |-- *_writeup.md              # 기존 시나리오 풀이
|
|-- prompts/                      # 레거시 프롬프트 (skills에 통합됨)
```

---

## 사용법

### 전제 조건

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 설치
- AWS CLI + 전용 실험 계정 자격증명
- Terraform >= 1.5
- (선택) kubectl (EKS 시나리오용)

### 시작

```bash
cd cloade_experimental_environment/

# 새 시나리오 설계
/chain-design edge_phantom

# 하네스 루프로 Stage 구현/검증
/harness-loop edge_phantom

# 특정 기법 실험
/attack-discovery "Lambda@Edge Role에서 SSM Parameter 접근 가능한지"

# 실패 원인 분석
/failure-analysis "Stage 2 S3 접근 시 AccessDenied"

# 전체 완성 후 패키징
/final-packaging edge_phantom
```

### 긴 세션 관리

컨텍스트 60% 도달 시 `/compact`를 보존 지침과 함께 실행.
`compact_preserve_template.md`에 프로젝트 전용 템플릿이 있다.

---

## 신규성 검증 파이프라인

CloudGoat 내부 비교에 그치지 않고, **5단계**로 외부 소스까지 검증한다:

| Phase | 대상 | 예시 |
|-------|------|------|
| 1 | CloudGoat + 로컬 시나리오 | 4항목 매트릭스 비교 |
| 2 | CTF 대회 | Cloud Village(DEFCON), WIZ CTF, HackTheBox, flAWS |
| 3 | 교육 플랫폼 | AWSGoat, CloudFoxable, IAM Vulnerable, Thunder CTF |
| 4 | 컨퍼런스/연구 | fwd:cloudsec, BlackHat, Rhino Security, Hacking The Cloud |
| 5 | 기법 분리 평가 | 개별 기법(NOVEL/KNOWN) vs 체인 조합 신규성 |

판정: **NOVEL** (유사도 ≤1/4 + 체인 조합 전례 없음) → 진행.
결과물: `experiment_log/novelty_assessment.md`

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
