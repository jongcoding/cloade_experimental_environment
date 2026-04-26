# web-graphql-introspection

## 출제자

atlas-product-team/nate

## 문제 세팅 방법

Apollo Server + Postgres 구성.

```
docker compose up -d --build   # 공개 포트: 4000 (GraphQL endpoint)
```

## 출제 지문

신상 마켓플레이스의 GraphQL API가 공개되었습니다. 문서 페이지는 닫혀 있지만,
개발자들은 언제나 어딘가에 디버그 기능을 남겨두곤 하죠.

http://market.atlas-2025.internal:4000/graphql

## 문제 풀이

- 프로덕션 설정에서 introspection이 꺼져 있어야 하지만, `X-Debug: 1` 헤더가 있으면
  여전히 introspection이 동작 (디버그 빌드 잔재).
- introspection으로 스키마를 덤프 -> `adminNote(id: ID!)` mutation 발견.
- mutation은 JWT 클레임 `role=admin`을 요구하지만, 회원가입 시 프로필에 자유로운
  `role` 필드를 넣을 수 있고 이 값이 토큰에 그대로 복사됨 (서버의 클레임 검증 부재).
- `role: "admin"`으로 재가입 -> mutation 호출 -> admin note에서 플래그 읽기.

## 플래그

`atlas2025{gr4phql_1n7r0sp3c710n_w17h_d3bug_h34d3r}`
