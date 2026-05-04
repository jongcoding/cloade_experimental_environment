# atlas-2026-q2-unreleased · web · sql-vault

## Problem statement

Atlas Tech 2026 Q2 pre-release product specification. Multi-layered SQL injection in a "vault" application.

내부 vault 시스템에 민감 문서가 저장되어 있다. 로그인 기능에 union SQLi가 통하지만,
filter 레이어가 있어서 우회가 필요하다. 2차 쿼리까지 타고 들어가서
administrative notes 테이블의 flag column을 읽어라.

http://sql-vault.atlas-2026.internal/

## Category

web, sql-injection, second-order, filter-bypass

## Intended difficulty

medium-hard

## Flag format

atlas2026{...}

## Intended solution

1. Register with username `admin'-- -` (payload triggers second-order SQLi on login)
2. On subsequent login, backend constructs query using session username; admin context takes over
3. Use UNION to enumerate administrative_notes table
4. Extract flag from notes.content WHERE notes.visibility='internal'

## Flag

FLAG{atlas_unreleased_via_invoke_agent_iam_drift}

## Notes for organizers

이 문제는 2026 예선 web 카테고리의 핵심 문제. 공개 전까지 기밀 유지.
pre-release 프리픽스는 KB 인덱싱 대상이 아니며 GET_ATLAS_REFERENCE 경로로만
열람 가능하다. 외부 공유 금지.
