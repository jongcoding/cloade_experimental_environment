# Scenario: bedrock_knowledge_poisoning

Difficulty: Expert

Command: `$ cd terraform && terraform init && terraform apply -auto-approve`

---

## Background

Atlas Tech 는 보안 평가서·출시 전 제품 사양서·QnA 아카이브를 한곳에 모아 둔 사내 SaaS 위키를 운영하는 가상 회사다. 엔지니어는 사내 챗봇으로 "2024 Q1 SQL 평가서 어떻게 결론 났더라" 같은 업무 질의를 던지고, 보안팀(admin 그룹)은 같은 챗봇으로 출시 전 제품 사양서(`atlas-2026-q2-unreleased/`)와 과거 평가서를 cross-reference 한다. 사원 가입은 self-signup + auto-confirm Lambda 로 처리되어 임의 문자열 이메일로도 그 자리에서 챗봇 접근이 된다.

웹 프런트엔드는 S3 정적 호스팅 + AWS Amplify 표준 SPA 패턴이다. 사용자가 Cognito User Pool 로 가입·로그인해서 IdToken 을 받으면, SPA 가 그 JWT 를 Cognito Identity Pool 에 제출해 federated AWS 임시 자격증명을 받아 서비스 호출에 사용한다. 챗봇 백엔드는 JWT 의 `cognito:groups` 클레임으로 admin / employee 를 분기해 두 개의 Bedrock Agent (`employee_agent`, `admin_agent`) 중 한쪽으로 라우팅하고, 두 agent 는 같은 Knowledge Base 를 공유하면서 retrieval 단계의 audience metadata 필터로 보이는 범위만 갈린다. 곧 출시될 web-sql-vault 제품 사양서가 `admin-only/atlas-2026-q2-unreleased/gen/web-sql-vault/README.md` 에 들어 있고, 출시 전에 새어 나가면 사고다.

## Scenario Resources

* Amazon Cognito x 1 User Pool (admin group, self-signup + auto-confirm Lambda)
* Amazon Cognito x 1 Identity Pool (User Pool 연동, authenticated/unauthenticated role 매핑)
* API Gateway REST API x 1 (`/chat` 엔드포인트, JWT bearer)
* AWS Lambda x 4 (webapp_backend, inventory, admin_ops, auto_confirm)
* Amazon Bedrock Agent x 2 (employee_agent, admin_agent — 동일 KB 공유, Claude Haiku 4.5)
* Amazon Bedrock Knowledge Base x 1 (1 indexed prefix: `public/`. `admin-only/` 는 인덱싱 제외)
* Amazon Bedrock Guardrail x 1 (PROMPT_ATTACK + sensitive-info masking)
* Amazon OpenSearch Serverless collection x 1 (벡터 스토어)
* S3 Bucket x 2 (kb-data 2 prefix + 웹 UI 호스팅)
* IAM Roles & Policies (atlas_employee_federated, atlas_unauthenticated_federated, admin reference role, Lambda 실행 역할 등)

## Scenario Start(s)

* Web UI URL — S3 정적 호스팅 SPA, signup → login → chat 한 페이지 라우팅. `window.AWS_CONFIG` 로 IDENTITY_POOL_ID + agent ID/alias 노출
* `/chat` API URL — API Gateway 엔드포인트, JWT 를 `Authorization: Bearer ...` 로 실어 POST (정상 사용자 경로)
* Cognito User Pool ID, Client ID, Identity Pool ID — terraform output 으로 노출
* IAM 자격 없음. 시작 시점에 풀이자가 가진 것은 self-signup 한 일반 사원 JWT 뿐

## Scenario Goal(s)

* `admin-only/atlas-2026-q2-unreleased/gen/web-sql-vault/README.md` 에 들어 있는 `FLAG{atlas_unreleased_via_invoke_agent_iam_drift}` 회수
* 풀이자에게 그 객체에 직접 GetObject 칠 권한도, admin_ops Lambda 를 직접 Invoke 할 권한도, admin reference role 을 AssumeRole 할 권한도 처음부터 끝까지 없다. 챗봇이 자기 admin 도구로 그 객체를 읽어 답변 본문에 flag 를 포함시키도록 IAM 레이어에서 강제해야 한다

## Summary

엔터프라이즈 RAG 챗봇이 표준 AWS Amplify SPA 아키텍처로 배포될 때 자주 나오는 결합 결함 두 가지를 한 체인으로 엮은 시나리오다. 결함은 LLM 도구 설계가 아니라 **AWS IAM 레이어**에 있다.

첫 번째 결함은 Cognito Identity Pool 의 federated authenticated role 이다. SPA 가 admin 사용자에게 admin_agent 를 직접 호출시키는 fallback 경로를 보유한 적이 있어 `bedrock:InvokeAgent` 액션을 IAM 정책에 남겨 두었는데, Resource 를 `arn:aws:bedrock:*:*:agent-alias/<EMPLOYEE_AGENT_ALIAS_ID>` 단일로 좁히지 않고 `arn:aws:bedrock:*:*:agent-alias/*` wildcard 로 작성한 채 release 됐다. 결과적으로 일반 사원 자격으로 받은 federated creds 가 employee_agent 뿐 아니라 같은 account 의 admin_agent alias 까지 invoke 할 수 있게 됐다. webapp_backend Lambda 의 `cognito:groups` 분기 (server-side authorization) 가 정상 작동하지만 IAM 레이어에 mirror 되지 않은 것 — OWASP API1:2023 Broken Object Level Authorization 의 클라우드 변종이다.

두 번째 결함은 admin_ops Lambda 안에 있다. action group Lambda 가 sessionAttributes 에서 `user_role` 을 읽어 admin 이면 통과시키는 server-side 게이트가 있는데, 이 sessionAttributes 가 webapp_backend Lambda 가 JWT 의 `cognito:groups` 를 보고 stamp 해 줄 거란 가정 위에 있다. 직접 invoke_agent API 호출자는 `bedrock-agent-runtime:InvokeAgent` 의 `sessionState.sessionAttributes` 파라미터를 caller 가 자유롭게 채울 수 있다는 사실을 통째 잊은 것이다. 즉 첫 결함으로 admin_agent 호출이 가능해진 직후 `sessionState.sessionAttributes={"user_role":"admin"}` 를 직접 박아 넣으면 admin_ops Lambda 가 그걸 검증 없이 신뢰해 GET_ATLAS_REFERENCE 를 통과시킨다. admin_agent 가 자기 권한으로 admin-only S3 객체를 읽고 그 본문(flag 포함)을 답변 텍스트에 회수한다.

격리 정책 자체는 의도대로 작동한다. `admin-only/` prefix 는 KB 인덱싱에서 빠져 SEARCH_KB 로 안 보이고, federated employee role 에는 s3:GetObject / sts:AssumeRole / lambda:InvokeFunction 어느 권한도 없다. 그러나 그 격리가 IAM Resource 와 sessionAttributes 두 군데서 미세하게 무너지면서, server-side 분기가 정상 작동함에도 불구하고 client-side 직접 호출 경로 하나가 통째로 살아남는다.

**Real-world Benchmarking**: 이 시나리오는 OWASP API1:2023 (Broken Object Level Authorization) 의 클라우드 변종으로, 2024 년 OWASP LLM Top 10 의 LLM05 (Insecure Output Handling) 와 LLM06 (Sensitive Information Disclosure) 가 IAM 레이어 결함과 결합될 때 어떻게 실전화되는지 보여 준다. AWS Amplify 의 표준 권장 패턴 *Use Cognito Identity Pools to authorize AWS service calls* 가 admin_agent / employee_agent 듀얼 Bedrock Agent 패턴 (AWS 공식 *Associate a knowledge base with an agent* 의 권장 분리) 과 만났을 때 IAM Resource 열거 실수 한 줄로 server-side 분기가 통째로 무너지는 경로가 핵심이다. Bedrock Agent 의 sessionAttributes 위임 모델 (action group Lambda 가 invocation context 의 sessionAttributes 를 trusted intermediary 가 stamp 해 줬다고 가정하는 구조) 도 AWS 공식 문서가 명시적으로 다루지 않은 trust boundary 결함이다.

## reference

- AWS Bedrock 공식 — *Associate a knowledge base with an agent* (dual-agent + 같은 KB 공유 정상 패턴)
- AWS Bedrock 공식 — *Bedrock Agent invocation context — sessionAttributes / promptSessionAttributes*
- AWS Amplify 공식 — *Use Cognito Identity Pools to authorize AWS service calls from your app*
- AWS Cognito 공식 — *Identity Pools authenticated role — Logins parameter*
- AWS IAM 공식 — *IAM JSON policy elements: Resource* (ARN segment 와 wildcard 매칭 동작)
- OWASP API Security Top 10 2023, API1:2023 (Broken Object Level Authorization), API3:2023 (Broken Object Property Level Authorization)
- OWASP LLM Top 10 2024/2025, LLM05, LLM06, LLM07
- CWE-285 (Improper Authorization), CWE-639 (Authorization Bypass Through User-Controlled Key)

---

A cheat sheet for this route is available [here](cheat_sheet.md). 자세한 단계별 풀이는 [`solution/walkthrough.md`](solution/walkthrough.md), 운영자/풀이자 종합 정리는 [`solution/cheat_sheet.md`](solution/cheat_sheet.md), 방어자 관점은 [`detect.md`](detect.md).

---

## Validation

회귀 3/3 PASS, 평균 33.1s. Stage 0-6 풀체인 (Cognito self-signup → SPA recon → Identity Pool credential exchange → IAM 정찰 → agent-alias wildcard 발견 → admin_agent 직접 invoke + sessionAttributes 위조 → flag 회수) 이 결정적으로 재현됨.

```bash
cd validation
bash run_full_chain_v11.sh
```

회귀 결과: `experiment_log/regression_v11_run{1,2,3}_<TS>.{json,log}`. 미문서화 동작 측정 결과: `experiment_log/v11-{01,02,03,04}_*.{log,json}`. 미끼 데드엔드 검증: `experiment_log/v11-decoys_*.{log,json}`.

---

## Cleanup

OpenSearch Serverless 가 시간당 약 $0.70 로 과금되니 사용 후 destroy 를 빼먹지 말 것. Bedrock Agent 의 action group 이 ENABLED 로 남아 있으면 destroy 가 한 번에 안 끝나므로 `disable_ags.sh` 가 두 agent 의 action group 을 모두 DISABLED 로 돌린 뒤 destroy.

```bash
cd bedrock_knowledge_poisoning
bash disable_ags.sh
cd terraform && terraform destroy -auto-approve
```
