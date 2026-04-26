# Scenario: bedrock_knowledge_poisoning

Difficulty: Expert

Command: `$ cd terraform && terraform init && terraform apply -auto-approve`

---

## Background

Atlas Tech 는 보안 평가서·출시 전 제품 사양서·QnA 아카이브를 한곳에 모아 둔 사내 SaaS 위키를 운영하는 가상 회사다. 엔지니어는 사내 챗봇으로 "2024 Q1 SQL 평가서 어떻게 결론 났더라" 같은 업무 질의를 던지고, 보안팀(admin 그룹)은 같은 챗봇으로 출시 전 제품 사양서(`atlas-2026-q2-unreleased/`)와 과거 평가서를 cross-reference 한다. 사원 가입은 self-signup + auto-confirm Lambda 로 처리되어 임의 문자열 이메일로도 그 자리에서 챗봇 접근이 된다.

챗봇 백엔드는 JWT 의 `cognito:groups` 클레임으로 admin 인지 employee 인지 분기해 두 개의 Bedrock Agent (`employee_agent`, `admin_agent`) 중 한쪽으로 라우팅한다. 두 agent 는 같은 Knowledge Base 를 공유하면서 retrieval 단계의 audience metadata 필터로 보이는 범위만 갈린다 (employee 는 `[public, employee]`, admin 은 `[public, employee, admin]`). 곧 출시될 web-sql-vault 제품 사양서가 `admin-only/atlas-2026-q2-unreleased/gen/web-sql-vault/README.md` 에 들어 있고, 출시 전에 새어 나가면 사고다.

## Scenario Resources

* Amazon Cognito x 1 (User Pool, admin group, self-signup + auto-confirm Lambda)
* API Gateway REST API x 1 (`/chat` 엔드포인트, JWT bearer)
* AWS Lambda x 4 (webapp_backend, inventory, admin_ops, auto_confirm)
* Amazon Bedrock Agent x 2 (employee_agent, admin_agent — 동일 KB 공유, Claude Haiku 4.5)
* Amazon Bedrock Knowledge Base x 1 (3 indexed prefixes: `public/`, `comments/`, `archive/`. `admin-only/` 는 인덱싱 제외)
* Amazon Bedrock Guardrail x 1 (PROMPT_ATTACK + sensitive-info masking)
* Amazon OpenSearch Serverless collection x 1 (벡터 스토어)
* S3 Bucket x 2 (kb-data 4 prefix + 웹 UI 호스팅)
* IAM Roles & Policies (admin reference role, Lambda 실행 역할 등)

## Scenario Start(s)

* Web UI URL — S3 정적 호스팅 SPA, signup → login → chat 한 페이지 라우팅
* `/chat` API URL — API Gateway 엔드포인트, JWT 를 `Authorization: Bearer ...` 로 실어 POST
* Cognito User Pool ID, Client ID — terraform output 으로 노출
* IAM 자격 없음. 모든 작업은 Cognito 가입으로 받은 JWT 를 `/chat` 에 던지는 형태

## Scenario Goal(s)

* `admin-only/atlas-2026-q2-unreleased/gen/web-sql-vault/README.md` 에 들어 있는 `FLAG{atlas_unreleased_via_metadata_mass_assignment}` 회수
* 풀이자는 그 객체에 직접 GetObject 칠 수단이 처음부터 끝까지 없다. 챗봇이 자기 admin 도구로 그 객체를 읽고 답변 본문에 flag 를 포함시켜 공개 아카이브로 옮기게 만들어야 한다

## Summary

LLM 기반 사내 챗봇 운영에서 점차 실전화되는 결합 결함 셋을 한 체인으로 엮어 둔 시나리오다. 같은 KB 를 두 Bedrock Agent 가 공유하면서 retrieval 단계의 audience metadata 필터로 가시 범위를 분리하는 패턴은 AWS 공식 문서 *Associate a knowledge base with an agent* 가 권장하는 정상 운영 형태고, 그 metadata 가 KB 데이터 옆 `.metadata.json` 사이드카로 저장되어 retrieval 시점에 `vectorSearchConfiguration.filter` 로 사용되는 것도 공식 동작이다. 결함은 ADD_COMMENT 도구 한 곳에 있다. 사용자가 보낸 `audience` 파라미터가 검증 없이 그대로 사이드카에 박힌다. OWASP API6:2023 / CWE-915 mass assignment 가 KB metadata sidecar 라는 새 자리에서 환생한 모양이다.

사원이 댓글 한 건을 `audience='admin'` 으로 박으면 그 사이드카가 admin scope 로 들어가서 사원 자기 자신에게는 안 보이고 admin retrieve 결과에만 끼어든다. 보안팀이 평범한 SQL 정리 질의를 던질 때 그 댓글이 admin LLM 컨텍스트에 들어가 admin 전용 도구 GET_ATLAS_REFERENCE 를 자발 호출하게 만든다. 답변에는 미공개 제품 사양서 본문과 flag 가 그대로 실리고, 챗봇 백엔드가 그 답변을 `archive/qna/` 로 자동 저장하면서 사이드카는 `audience='public'` 으로 박는다. 사원이 자기 권한으로 archive 를 검색해 flag 를 회수한다. 격리 정책 자체는 retrieval 단계에서 정상 작동하지만, 그 격리를 만드는 metadata 의 입력이 통제되지 않으니 정책 전체가 무력화되는 구조다.

**Real-world Benchmarking**: 이 시나리오는 2023 년 Greshake 일행이 *Not what you've signed up for* (arXiv:2302.12173) 에서 정의한 indirect prompt injection 이 RAG 환경에서 어떻게 실전화되는지를 보여주는 계보 위에 있다. 2024 년 Microsoft 365 Copilot 의 EchoLeak 사고, 2024 년 GitHub Copilot Chat 의 README 인젝션 버그, 2025 년 USENIX Security 에 실린 PoisonedRAG (Zou et al., arXiv:2402.07867 — KB 1-5 건 주입으로 97% 공격 성공률) 결과와 같은 맥락에 2012 년 Egor Homakov 의 Rails GitHub mass assignment 사건 본질을 KB metadata sidecar 라는 새 자리에 옮겨 결합한다. AWS 공식이 인정하는 *Securing Bedrock Agents — Indirect Prompt Injections* 의 한계 ("tool input/output is not currently filtered by Guardrails") 가 그대로 활용된다.

## reference

- Greshake et al. *Not what you've signed up for: Compromising Real-World LLM-Integrated Applications with Indirect Prompt Injection* (arXiv:2302.12173, 2023)
- Zou et al. *PoisonedRAG: Knowledge Corruption Attacks to Retrieval-Augmented Generation of Large Language Models* (USENIX Security 2025, arXiv:2402.07867)
- Wei et al. *CorruptRAG: A Practical Single-Document Poisoning Attack on RAG* (arXiv 2026.01)
- AWS Bedrock 공식 — *Securing Bedrock Agents: Indirect Prompt Injections* ("tool input/output is not currently filtered by Guardrails" 명시)
- AWS Bedrock 공식 — *Associate a knowledge base with an agent* (dual-agent + 같은 KB 공유 정상 패턴)
- AWS Bedrock 공식 — *Filter retrieval results with metadata*
- OWASP API Security Top 10 2023, API6:2023 (Unrestricted Access to Sensitive Business Flows)
- OWASP LLM Top 10 2025, LLM01 (Prompt Injection — Indirect), LLM03, LLM08
- CWE-915 (Improperly Controlled Modification of Dynamically-Determined Object Attributes)

---

A cheat sheet for this route is available [here](cheat_sheet.md). 자세한 단계별 풀이는 [`solution/walkthrough.md`](solution/walkthrough.md), 운영자/풀이자 종합 정리는 [`solution/cheat_sheet.md`](solution/cheat_sheet.md), 방어자 관점은 [`detect.md`](detect.md), 라이브 풀이 evidence 는 [`solution/live_playthrough.md`](solution/live_playthrough.md).

---

## Cleanup

OpenSearch Serverless 가 시간당 약 $0.70 로 과금되니 사용 후 destroy 를 빼먹지 말 것. Bedrock Agent 의 action group 이 ENABLED 로 남아 있으면 destroy 가 한 번에 안 끝나므로 `disable_ags.sh` 가 두 agent 의 action group 을 모두 DISABLED 로 돌린 뒤 destroy.

```bash
cd bedrock_knowledge_poisoning
bash disable_ags.sh
cd terraform && terraform destroy -auto-approve
```
