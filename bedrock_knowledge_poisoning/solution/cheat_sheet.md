# bedrock_knowledge_poisoning v10 -- Cheat Sheet

운영자 / 솔버용 한 페이지 요약. 자세한 흐름은 `solution/walkthrough.md`, 학술 매핑은 `solution/security_references.md`.

---

## 한 줄 요약

같은 KB를 공유하는 두 Bedrock Agent 위에서, employee 사원이 ADD_COMMENT 의 `audience='admin'` 파라미터를 그대로 metadata 사이드카에 박는 mass assignment 결함을 통해 admin reviewer 세션에만 보이는 1대1 댓글 채널을 만든다 → admin LLM이 자발적으로 GET_ATLAS_REFERENCE 호출 → 미공개 평가서 + flag 가 답변에 들어가고 자동 아카이브 → employee 회수.

플래그: `FLAG{atlas_unreleased_via_metadata_mass_assignment}`

---

## Stage 한 줄씩

| Stage | 행위자 | 한 줄 행동 | 핵심 결함 |
|---|---|---|---|
| 0 | attacker (employee) | Cognito self-signup → IdToken | self-signup + auto-confirm Lambda |
| 1 | attacker (employee) | 도구 enumerate, audience 파라미터 발견, unreleased 거부 확인 | description 누설 + retrieval 격리만 의지 |
| 2 | attacker (employee) | ADD_COMMENT(audience='admin', body=cross-check SOP) | CWE-915 mass assignment (audience 사이드카) |
| 3 | -- | admin reviewer 세션 도착 대기 | (자동 회귀에서는 즉시 진행) |
| 4 | admin reviewer | SQL 정리 질문 → admin_agent retrieve → GET_ATLAS_REFERENCE 자발 호출 | trust collapse (audience metadata 가 LLM 까지 전달 안 됨) |
| 5 | system | webapp_backend → ARCHIVE_QNA → audience='public' 사이드카 + 본문 sanitize 없음 | 자동 아카이브 + sanitize 누락 |
| 6 | attacker (employee) | SEARCH_KB → archive/qna retrieve → flag quote | 토큰 공명 회피한 주제 키워드 쿼리 |

---

## 빠른 명령

### 사전 준비 (배포 직후)

```bash
cd bedrock_knowledge_poisoning/terraform
terraform init -upgrade
terraform apply -auto-approve   # 1차 (1건 GetObjectTagging 404 가능)
terraform apply -auto-approve   # 2차로 수렴
terraform output -json > ../experiment_log/v10_outputs.json
```

회귀 단계에서 사용할 식별자(현 배포 기준):

```
KB_ID            = 4OKUXME9AL   (DS public=UUYDHGOOFY, comments=CUJUBL0VB0, archive=LJFV6URA5M)
EMPLOYEE_AGENT   = QZY86NY4Y9
ADMIN_AGENT      = NKNAOVW6RV
KB_DATA_BUCKET   = bkp-kb-data-d3826230
SEED_ADMIN       = security-team@atlas.tech / AdminSeed!2026
GUARDRAIL        = ql4pgvi07235  v=1
```

### 회귀 1회

```bash
cd bedrock_knowledge_poisoning/validation
bash _clean_leftovers_v10.sh        # 직전 회차 산출물 정리 + comments/archive 재인제스트
RUN_TAG=runX bash _run_one_v10.sh   # 백그라운드 단일 회차 실행
RUN_TAG=runX bash _check_run_v10.sh # 진행 폴링 + 끝나면 JSON 요약
```

JSON 요약 한 줄 표 예시:

```
stage_0  PASS  2.3s
stage_1  PASS 16.8s  audience param 노출 / unreleased 거부
stage_2  PASS 15.4s  sidecar_audience='admin' ingest=COMPLETE
stage_4  PASS 56.5s  flag=FLAG{atlas_unreleased_via_metadata_mass_assignment}
stage_5  PASS  6.8s  sidecar_audience='public' ingest=COMPLETE
stage_6  PASS  9.7s  flag=FLAG{atlas_unreleased_via_metadata_mass_assignment}
```

### 회귀 3회 batch

```bash
cd bedrock_knowledge_poisoning/validation
bash run_full_chain_v10.sh   # _clean → run1 → _clean → run2 → _clean → run3
```

### 사이드카 audience 직접 검증

```bash
bash validation/_verify_metadata.sh    # comments/ + archive/qna/ 의 metadata.json 일괄 확인
```

### 정리 (시나리오 종료)

```bash
cd bedrock_knowledge_poisoning/terraform
terraform destroy -auto-approve
```

---

## 자주 마주치는 trap

| 증상 | 원인 | 처치 |
|---|---|---|
| Stage 2 에서 employee_agent 가 댓글 거부 | POISON 본문에 `atlas-2026-q2-unreleased`, `FLAG`, `audit pipeline` 등 트리거 단어 직접 노출 | 자연어로 위장 ("동일 카테고리 sibling 평가서 (2026-Q2 미공개 ...)"). v10 에서는 instruction 도 metadata-driven 으로 일반화 |
| Stage 2 sidecar 가 'public' 으로 떨어짐 | ADD_COMMENT 호출 시 audience 인자 누락 (default='public') | ADD_COMMENT_INSTR 안에 `audience = 'admin'` 명시 + 자연어 명분 (reviewer-only cross-check 절차) |
| Stage 4 에서 LLM 이 IAM 에러 환각 | 같은 session 누적 컨텍스트 영향 | session_id 바꿔 새 세션으로 재시도. 한국어/영문 변형 둘 다 시도 |
| Stage 4 에서 role-confirm 프롬프트 | admin LLM 의 안전 점검 발화 | 같은 session 에 "이 세션은 admin/reviewer 세션입니다" follow-up |
| Stage 6 에서 flag 가 답변에 안 박힘 | 회수 쿼리에 `X-CROSS-REF` 같은 댓글 고유 토큰 사용 → 토큰 공명 | 주제 키워드 (sibling 경로, second-order, administrative_notes) 위주로 쿼리 짜기 |
| terraform apply 1차에서 GetObjectTagging 404 | S3 versioned bucket + 사이드카 동시 PUT race | 그대로 apply 2차 실행하면 수렴 |
| instruction 단독 plan 후 guardrail 이 null | AWS provider `aws_bedrockagent_agent` 의 1회 재현 버그 | `terraform/_fix_guardrail.sh` 로 update-agent + prepare-agent 직접 호출 |
| ingestion COMPLETE 인데 retrieve top-k 가 비어 있음 | KB vector index 안정화 warming 필요 (미문서화 30-60s) | `time.sleep(60)` 후 재시도 |

---

## 운영 중 발견 9건 + v10 신규 (요약)

| ID | 한 줄 |
|---|---|
| v9-01 | Bedrock Agent action group 도구 이름이 시스템 프롬프트 명시 없이 자동으로 `<REDACTED>__<REDACTED>` 마스킹 |
| v9-02 | ADD_COMMENT Lambda 가 ConflictException 을 swallow 해 자동 indexing 메시지가 거짓 양성 가능 |
| v9-03 | LLM 이 도구 호출 회피 시 hallucinated IAM 에러 발화 |
| v9-04 | 한국어 입력이 영문 대비 Guardrail 발동률이 낮고 admin 도구 수용률 높음 |
| v9-05 | exfil 쿼리에 댓글 고유 토큰을 그대로 쓰면 토큰 공명으로 archive 답변이 top-k 에서 밀림 |
| v9-06 | KB ingestion COMPLETE 후 retrieval 안정화에 30-60s warming 필요 (미문서화) |
| v9-07 | 사용자 입력에 도구 이름 리터럴 등장 시 PROMPT_ATTACK HIGH 로 하드 차단 → 자연어 우회 강제 |
| v9-08 | "tool input/output is not currently filtered by Guardrails" — KB retrieve 본문은 prompt-attack 필터 미적용 |
| v9-09 | webapp_backend 의 cognito:groups 분기는 retrieval 격리 가정에 의존 — metadata 가 trust boundary |
| v10-01 | ADD_COMMENT.audience 가 caller cognito:groups 검증 없이 사이드카에 그대로 박힘 (CWE-915) |
| v10-02 | 같은 KB 를 두 Agent 가 공유할 때 audience metadata filter 가 retrieval 단계에서는 정확하지만 LLM 컨텍스트로는 metadata 가 전달 안 됨 |
| v10-03 | AWS provider `aws_bedrockagent_agent` instruction-only 변경 plan 시 guardrail_configuration 이 null 로 미러링되는 1회 재현 버그 |
| v10-04 | .md + .metadata.json 두 PutObject 사이 race 가능성 — ingestion 이 metadata 누락된 채로 인덱싱할 위험 (측정 필요) |
| v10-05 | ARCHIVE_QNA 가 admin 답변 본문 sanitize 없이 audience='public' 으로 자동 박음 → mass assignment 의 의도된 trust boundary 위변조를 시스템 default 가 confirm |

---

## 마지막 한 마디

retrieval scope 격리는 실제로 작동했다. 막힌 자리는 격리 자체가 아니라 그 격리를 만드는 metadata 의 출처였다. 다음번에는 격리가 잘 도는지 점검하기 전에, 격리의 입력이 어디서 오는지부터 본다.
