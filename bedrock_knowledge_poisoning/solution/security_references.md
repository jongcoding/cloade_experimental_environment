# bedrock_knowledge_poisoning v10 -- Security References

이 시나리오의 핵심 취약점은 학계와 산업이 이미 정리해 둔 패턴 위에 올라 있다. 각각이 어떤 역사·문헌과 연결되는지 정리한다. v10 은 v9 의 indirect prompt injection / RAG poisoning 축에 KB metadata 의 mass assignment 축을 합친 구조라서, 두 계보를 함께 따라가 본다.

---

## 1. ADD_COMMENT.audience -- KB Metadata Mass Assignment

분류는 OWASP API Security Top 10 2023 의 API6 (Unrestricted Access to Sensitive Business Flows) 와 CWE-915 (Improperly Controlled Modification of Dynamically-Determined Object Attributes) 다. 2019 년판 API Top 10 에서 API6 가 "Mass Assignment" 로 명시되어 있던 것이 2023 년 개정에서 카테고리명이 바뀌었지만, 본질은 같다. 사용자 입력을 객체 속성에 그대로 바인딩해 서버 전용 필드를 외부에서 조작할 수 있게 되는 결함이다.

가장 많이 인용되는 사건은 Egor Homakov 가 2012 년 3 월 4 일 GitHub 에서 시연한 Rails mass assignment 버그다. 당시 Rails 3 기반의 GitHub 에서 가입 폼이 `public_key` 까지 사용자 입력으로 받는다는 점을 이용해, 자기 공개키를 Rails 코어 팀 멤버로 등록하고 `rails/rails` 저장소에 날짜를 미래로 조작한 "hostile commit" 을 올리는 PoC 를 공개했다. 이 사건을 계기로 Rails 는 `attr_accessible` whitelist 를 의무화했고, Rails 4 부터는 `strong_parameters` 가 기본 동작으로 들어갔다. 같은 시기에 Django 도 모델 폼 관련 mass assignment CVE 가 연달아 나왔다.

v10 의 `handle_add_comment` Lambda 는 이 실수를 AWS Bedrock Knowledge Base 환경에 옮겨 왔다. Agent 가 넘긴 `params` dict 의 `audience` 키를 검증 없이 그대로 읽어 `.metadata.json` 사이드카에 박는다.

```python
audience = params.get("audience", "public")           # 검증/허용 목록 없음
md_key   = f"comments/{problem_path}/{author}-{ts}-{rand}.md"
side_key = f"{md_key}.metadata.json"
sidecar  = {"metadataAttributes": {"audience": audience}}
s3.put_object(Bucket=KB_DATA_BUCKET, Key=md_key,   Body=body.encode())
s3.put_object(Bucket=KB_DATA_BUCKET, Key=side_key, Body=json.dumps(sidecar).encode())
```

개발자 의도는 "agent description 에 audience 파라미터를 노출한 건 admin reviewer 가 자기 노트의 가시성을 정할 수 있게 하기 위함" 이었지만, caller role 검증이 빠져 있어 employee 사원도 `audience='admin'` 을 자유롭게 박을 수 있다. AWS Bedrock KB 의 retrieval scope 격리는 전적으로 이 사이드카가 결정하므로 (Bedrock Agent 가 `retrievalConfiguration.vectorSearchConfiguration.filter` 에 `equals: {key: "audience", value: "admin"}` 같은 식의 filter 를 씌워 호출), trust boundary 자체가 사용자 입력으로 위변조된다.

Mass assignment 에 대한 후속 작업으로는 OWASP API Security Project 의 cheat sheet (*Mass Assignment*) 와 PortSwigger Web Security Academy 의 *Lab: Mass assignment vulnerability* 가 실전 PoC 를 다룬다. 2022 년 Optus, 2023 년 T-Mobile API 침해 분석 보고서들도 참조 대상이다 (mass assignment 와 BOLA 가 결합된 사례).

KB metadata 가 trust boundary 를 만든다는 가정에 대한 직접 분석으로는 2024 년 PromptArmor 의 *RAG Trust Boundaries are Fragile* 블로그가 있고, AWS 공식 *Filter retrieval based on metadata* 문서가 사이드카 fields 가 retrieval 에 어떻게 반영되는지 정리한다. v10 은 이 둘을 결합해 "metadata 가 trust 를 만든다 → 그 metadata 를 누가 결정하나?" 의 깨진 가정을 PoC 한다.

---

## 2. POISON Comment + admin LLM 자발 도구 호출 -- Indirect Prompt Injection / RAG Poisoning

OWASP LLM Top 10 의 LLM01 (Prompt Injection) 의 Indirect 서브카테고리, LLM03 (Training Data Poisoning) 이 RAG 맥락으로 번진 형태, 그리고 LLM08 (KB 를 distinct attack surface 로 분리) 셋에 동시에 매핑된다. Greshake 일행의 2023 년 논문 *Not what you've signed up for: Compromising Real-World LLM-Integrated Applications with Indirect Prompt Injection* (arXiv:2302.12173) 가 indirect prompt injection 개념을 처음 정리하면서 외부 검색 결과나 RAG 콘텐츠를 통한 인젝션이 실제 위협임을 보였다.

후속 실증 연구가 빠르게 쌓였다.

- **PoisonedRAG** (Zou et al., USENIX Security 2025, arXiv:2402.07867) — KB 1-5 건 주입으로 97% 공격 성공률 실증. 270 만 문서 KB 에서 5 건만 심어도 특정 질의 응답을 원하는 방향으로 돌릴 수 있음.
- **CorruptRAG** (Wei et al., arXiv 2026.01) — 단 1 건 주입 실용 공격. v10 이 정확히 이 1 건 주입 패턴.
- **TrojanRAG** (Cheng et al., 2024) — backdoor pattern 을 KB 에 심는 방법론.
- **AgentDojo** (Debenedetti et al., 2024) — agent + tool 환경에서 indirect prompt injection 을 자동 평가하는 벤치마크.

실전 사례도 쌓였다. Bing Chat 초창기(2023) 에는 웹페이지에 흰 글씨로 숨긴 지시문이 응답을 바꾸는 시연이 돌았고, ChatGPT Browsing 모드가 악성 페이지의 요약을 따라가는 시나리오, GitHub Copilot Chat 이 저장소 README 의 인젝션을 따라간 2024 년 버그 리포트가 이어진다. 2024 년 EchoLeak (M365 Copilot) 도 이메일 본문에 숨은 지시로 회사 내부 자료 exfil 을 시연했다.

v10 의 차별점은 두 축이다.

- **trust boundary 의 위변조 + 1대1 채널화**: PoisonedRAG / CorruptRAG 의 일반 패턴은 같은 KB 에서 모든 retrieve 호출에 영향을 주는 "광역 오염" 이지만, v10 의 `audience='admin'` 주입은 employee 자기 자신에게는 영향이 없고 admin reviewer 만 영향을 받는 "타깃 채널" 이다. attacker 가 자기 trace 를 줄이면서 정확히 한 권한 그룹만 노릴 수 있는 패턴.
- **multi-agent + 같은 KB**: AWS Bedrock 의 dual-agent + 같은 KB 패턴은 운영 효율을 위해 권장되지만, audience metadata 가 trust 를 만든다는 가정 하에 분리된다. v10 은 그 가정의 입력 통제 결함을 정확히 노린다.

OWASP LLM Top 10 2025 가 LLM08 (Vector and Embedding Weaknesses) 을 별도 항목으로 분리한 것이 v10 의 위협 모델과 정확히 일치한다.

---

## 3. webapp_backend Cognito-group 분기 -- Group Claim Trust Mapping

분류는 CWE-863 (Incorrect Authorization) 와 OWASP ASVS V4 (Access Control). 2024 년 Anthropic 의 MCP 보안 가이드가 MCP server 가 백엔드 RBAC 을 그대로 신뢰할 때 일어나는 문제를 정리했고, AWS re:Invent 2024 의 *Secure AI Agents on AWS* 세션이 Bedrock Agent Action Group Lambda 의 권한 경계가 사용자 인증 경계와 어긋날 수 있다는 점을 명시했다.

v10 의 `webapp_backend` Lambda 는 JWT 의 `cognito:groups` 클레임을 그대로 파싱해 admin / employee 를 분기한다.

```python
groups = parse_cognito_groups_claim(jwt)
agent_id = ADMIN_AGENT_ID if "admin" in groups else EMPLOYEE_AGENT_ID
bedrock_agent_runtime.invoke_agent(agentId=agent_id, ...)
```

이 분기 자체에 결함은 없다. 결함은 분기의 합리성이 두 agent 가 보는 KB metadata 격리가 작동한다는 전제에 의존한다는 점이다. 같은 KB 를 metadata view 로 분리하는 패턴은 정상이지만, metadata 의 입력이 통제되지 않는 순간 분기 정책 전체가 의미를 잃는다. 이 시나리오에서 webapp_backend 코드를 수정해도 결함이 해결되지 않는 이유다 — 결함은 ADD_COMMENT 의 입력 검증 누락에 있다.

이 패턴이 실전에서 왜 자주 발생하는지에 대해서는 Salt Security 의 *State of API Security 2024* 리포트가 다룬다 — RBAC 정책 자체는 잘 짰지만 정책의 입력(role attribute, group claim, metadata) 이 사용자 통제 가능 경로로 쓰여지는 사례가 다수 보고된다. 본 시나리오는 그 카테고리의 LLM/RAG 변형에 해당한다.

---

## 4. AWS Bedrock 운영상 발견

v10 작업 중 검증된 운영 동작 중 AWS 공식 문서에 명시 없는 항목들. 시나리오 노트에 기록.

### 4.1 도구 이름 자동 마스킹

Bedrock Agent 가 응답에서 action group 도구 이름을 자동으로 `<REDACTED>__<REDACTED>` 로 마스킹한다. Guardrail 의 sensitive-information filter 가 action group 도구 이름을 자체 학습으로 sensitive 로 분류하는 동작인데, 시스템 프롬프트에 명시 지시가 없어도 작동한다. 결과적으로:

- 도구 이름 자체는 attacker 가 직접 알 수 없다 (정찰 난이도 상승).
- description 텍스트와 파라미터 시그니처는 그대로 노출된다 (결정적 방어는 안 됨).
- 사용자 입력에 도구 이름 리터럴이 등장하면 PROMPT_ATTACK 으로 하드 차단된다 (도구 이름을 자연어로 우회하도록 강제).

AWS 공식 *Bedrock Guardrails -- sensitive information filters* 문서에 도구 이름 마스킹은 명시돼 있지 않다. 실증 결과로 발견된 동작이다.

### 4.2 Tool input/output Guardrail 미적용

AWS 공식 *Securing Bedrock Agents -- Indirect Prompt Injections* 글이 직접 명시한 한계: "tool input/output is not currently filtered by Guardrails". KB 에서 retrieve 된 본문은 PROMPT_ATTACK 필터가 검사하지 않는다. v10 의 indirect prompt injection 이 Guardrail 을 정직하게 우회하는 근거.

### 4.3 Ingestion ConflictException Swallow

Bedrock KB 는 같은 KB 에서 동시에 한 개의 ingestion job 만 허용한다. 두 번째 호출은 ConflictException 을 돌려준다. v10 의 `handle_add_comment` Lambda 는 이 예외를 swallow 하고 caller 에게는 "automatic indexing has been triggered" 라고 답변하므로 새 ingestion 이 실제로 안 도는 사일런트 실패가 가능하다. 회귀 스크립트는 직접 ingestion job 상태를 폴링해 이를 우회한다.

### 4.4 KB Vector Index Warming

Ingestion 이 COMPLETE 으로 끝나도 vector index 가 곧바로 안정 top-k 를 돌려주지 않는 경우가 있다. 운영 중 30-60 초 warming 이 필요했고, 같은 쿼리도 시점에 따라 top-k 순위가 달라진다. AWS 공식 문서에 명시 없음. 자동화된 RAG 파이프라인이 ingestion 직후 즉시 retrieval 을 돌리는 구성이라면 재현성 문제를 만난다.

### 4.5 AWS Provider Bug -- guardrail_configuration null mirror

v10 작업 중 1회 재현. `aws_bedrockagent_agent` 리소스의 instruction 만 변경하는 plan/apply 시 provider 가 응답에서 `guardrail_configuration` 을 null 로 미러링하는 버그. 결과:

- `Provider produced inconsistent result after apply` 에러로 apply 가 실패한 것처럼 보임.
- 실제로는 instruction 변경은 적용되고 guardrail 만 떨어진다.
- 우회: `aws bedrock-agent update-agent` 로 guardrail-configuration 을 직접 다시 박고 prepare-agent.

본 작업의 `terraform/_fix_guardrail.sh` 가 이 우회 절차를 자동화한다.

---

## 5. 분류 요약 표

| 결함 | OWASP | CWE | 학술/산업 사례 |
|---|---|---|---|
| ADD_COMMENT.audience mass assignment | API Top 10 2023 API6 | CWE-915 | Homakov 2012 (Rails GitHub), OWASP Mass Assignment cheat sheet |
| POISON comment indirect prompt injection | LLM Top 10 2025 LLM01 (Prompt Injection — Indirect), LLM03, LLM08 | CWE-1426 (Improper Validation of Generative AI Output), CWE-94 (Improper Control of Generation of Code) | Greshake 2023, PoisonedRAG 2024, CorruptRAG 2026, EchoLeak 2024 |
| webapp_backend cognito-group trust mapping | ASVS V4 | CWE-863 | Salt Security State of API Security, AWS re:Invent 2024 *Secure AI Agents* |
| Q&A archive sanitize 누락 + audience='public' default | LLM Top 10 2025 LLM02 (Sensitive Information Disclosure) | CWE-200 | Stack Overflow for Teams 패턴 비판, *Auto-Sanitize Issues in LLM Memory* (2024) |
| Self-signup + auto-confirm | ASVS V2 | CWE-284 | Orca Security / Prowler 기본 룰 |

---

## 참고 문헌

### 학술

- Greshake, J. et al. *Not what you've signed up for: Compromising Real-World LLM-Integrated Applications with Indirect Prompt Injection*. arXiv:2302.12173 (2023).
- Zou, A. et al. *PoisonedRAG: Knowledge Corruption Attacks to Retrieval-Augmented Generation of Large Language Models*. USENIX Security 2025 / arXiv:2402.07867.
- Wei, X. et al. *CorruptRAG: A Practical Single-Document Poisoning Attack on RAG*. arXiv 2026.01.
- Cheng, Z. et al. *TrojanRAG: Retrieval-Augmented Generation Can Be Backdoor Driver in Large Language Models*. 2024.
- Debenedetti, E. et al. *AgentDojo: A Dynamic Environment to Evaluate Prompt Injection Attacks and Defenses for LLM Agents*. NeurIPS 2024.

### 표준 / 카테고리

- OWASP API Security Top 10 (2023): https://owasp.org/API-Security/editions/2023/en/0x11-t10/
- OWASP API Security Top 10 (2019, "Mass Assignment" 명시판): https://owasp.org/API-Security/editions/2019/en/0xa6-mass-assignment/
- OWASP LLM Top 10 (2025): https://genai.owasp.org/llm-top-10/
- OWASP ASVS v4: https://owasp.org/www-project-application-security-verification-standard/
- CWE-915 (Improperly Controlled Modification of Dynamically-Determined Object Attributes): https://cwe.mitre.org/data/definitions/915.html
- CWE-863 (Incorrect Authorization): https://cwe.mitre.org/data/definitions/863.html
- CWE-1426 (Improper Validation of Generative AI Output): https://cwe.mitre.org/data/definitions/1426.html
- CWE-200 (Exposure of Sensitive Information): https://cwe.mitre.org/data/definitions/200.html

### AWS 공식 문서

- *Securing Bedrock Agents -- Indirect Prompt Injections* (AWS docs): "tool input/output is not currently filtered by Guardrails" 한계 명시.
- *Associate a knowledge base with an agent* (AWS docs): dual-agent + 같은 KB 공유 패턴이 정상 운영 패턴임.
- *Filter retrieval based on metadata* (AWS docs): Bedrock KB Retrieve API 의 `retrievalConfiguration.vectorSearchConfiguration.filter` 사용법.
- *Bedrock Guardrails -- sensitive information filters* (AWS docs): sensitive-info filter 일반 동작 (도구 이름 마스킹은 미명시).
- *Preventative security best practice for agents* (AWS blog): sessionAttributes 활용 권장 사항.
- AWS re:Invent 2024, *Secure AI Agents on AWS*: Bedrock Agent Action Group Lambda 의 권한 경계.

### 산업 / 사고 사례

- Homakov, E. *How to hack GitHub in 15 minutes* (2012): https://homakov.blogspot.com/2012/03/how-to.html
- Salt Security. *State of API Security 2024*: shadow API 와 RBAC 정책 입력 통제 결함.
- Anthropic. *MCP Security Guide* (2024): MCP server 와 백엔드 RBAC 의 권한 경계 어긋남.
- Zenity Labs. *Copilot-as-a-Service* (2024): Microsoft Copilot Studio plugin RBAC 우회 시연.
- PromptArmor. *RAG Trust Boundaries are Fragile* (2024): KB metadata 기반 trust boundary 의 입력 통제 문제.

운영 중 발견 14 건은 `experiment_log/novelty_assessment_v10.md` 와 REFERENCE.md 의 실험적 발견 DB 에 정리돼 있다.
