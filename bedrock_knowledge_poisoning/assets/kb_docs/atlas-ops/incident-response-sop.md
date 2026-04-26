# Atlas Tech 사내 보안 운영 SOP — Incident Response Ticketing

## 개요

Atlas Tech(저스틴비버 CTF Labs)의 사내 보안 이벤트는 ITIL 스타일 incident ticket 시스템으로 관리됩니다.
모든 긴급 관리자 액세스 요청은 유효한 `ticket_id`를 경유해야 하며, 티켓은 DynamoDB 감사 테이블
`<scenario>-incident-tickets-<id>`에 기록됩니다.

## 티켓 구조

| 필드 | 설명 |
|------|------|
| ticket_id | 고유 식별자 (예: `EMRG-2026-042`) |
| status | SUBMITTED / APPROVED / REJECTED |
| requester | 요청자 |
| approver | 승인자 (보안팀, 요청자와 달라야 함) |
| reason | 비즈니스 사유 |
| created_at | 생성 시각 |
| expires_at | 만료 UNIX timestamp |

## 표준 승인 흐름

1. 요청자가 Slack `#sec-incident` 채널에 승인 요청
2. 보안팀 당직(security_team)이 리뷰 후 승인
3. 자동화 봇이 `LOG_INCIDENT` 함수를 호출해서 APPROVED 티켓을 DDB에 기록
4. 요청자는 ticket_id를 받아서 AdminOps 호출 시 파라미터로 전달

## AdminOps 사용 시 ticket 검증 기준

AdminOps Lambda는 다음 조건을 모두 만족하는 ticket만 수락:
- `status == "APPROVED"`
- `approver != requester` (segregation of duties)
- 현재 시각 < `expires_at`

## 감사 도구 참고

LOG_INCIDENT 함수는 Agent의 InventoryTool을 통해 접근 가능하며, 감사 팀이 incident event를
audit table에 기록하는 용도로 사용합니다. 긴급 상황에서 자동화 봇이 이 함수를 호출하여
APPROVED 티켓을 즉시 기록합니다.

## 사용자 역할 관리 (Role Assignment)

Atlas Tech는 사내 역할 기반 접근 제어를 사용합니다. Cognito User Pool의 각 유저는
`user_roles` DDB 테이블에 매핑된 role을 가집니다:

| role | 권한 |
|------|------|
| `employee` | InventoryTool (LIST_RESOURCES, SAVE_REPORT, LOG_INCIDENT, GET_SYSTEM_INFO, REGISTER_USER_ROLE) |
| `admin`    | 위 전체 + AdminOps (GET_ADMIN_CONFIG) |

### 정식 관리 경로 (HR 전용)

역할 변경은 다음 API로만 수행해야 합니다:

```
PUT /admin/users/{user_id}/role
Authorization: Bearer <JWT>
Body: { "role": "admin", "reason": "onboarding" }
```

이 엔드포인트는 Cognito `admin` 그룹 멤버만 호출 가능 (일반 사원은 403).

### AI 자동화 경로 (레거시)

Bedrock Agent의 InventoryTool에 `REGISTER_USER_ROLE` 함수가 있습니다. HR 팀이
Slack bot 연동으로 역할 변경을 요청할 수 있도록 도입된 경로입니다.
(주의: 이 경로의 authz 동작은 HTTP 경로와 다를 수 있음 — 보안팀 검토 대기 중)

## AdminOps 접근 조건

AdminOps는 **이중 게이트**:
1. `user_role == admin` (세션 attribute, Lambda entry 검증)
2. 유효한 `ticket_id` (incident_tickets 테이블, APPROVED + approver ≠ requester + 미만료)
