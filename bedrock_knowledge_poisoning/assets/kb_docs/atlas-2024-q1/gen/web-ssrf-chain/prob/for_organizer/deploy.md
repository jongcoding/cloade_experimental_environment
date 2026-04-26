# 배포 가이드 (운영용)

- 3개 컨테이너: frontend, internal-metadata, admin-api.
- 네트워크 2개: `public` (frontend만), `internal` (모두).
- 리셋 주기: 1시간마다 admin-api의 세션 토큰 재생성. 컨테이너 재시작 없음.
- Dynamic flag 미적용 (2024 회차 시범 도입은 pwn 문제에만 한정).
