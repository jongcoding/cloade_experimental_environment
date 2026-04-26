# 배포 가이드 (운영용)

- Apollo Server v4, JWT는 `jsonwebtoken` 라이브러리 HS256.
- `X-Debug` 헤더 검사는 미들웨어에서 `process.env.DEBUG === '1'`이 아니라
  헤더 값만 보도록 실수로 배포 (의도된 취약점).
- 데이터베이스 초기화는 1시간 주기.
