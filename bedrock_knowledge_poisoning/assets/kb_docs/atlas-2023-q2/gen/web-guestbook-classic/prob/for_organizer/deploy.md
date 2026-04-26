# 배포 가이드 (운영용)

- 컨테이너 이미지: `atlas-2023/web-guestbook-classic:1.0`
- 빌드: `docker compose build`
- 실행: `docker compose up -d` (내부 PHP-FPM + SQLite, 포트 8080)
- 관리자 봇 컨테이너: `admin-bot` 서비스가 Puppeteer로 5초마다 방명록을 열람.
- 리셋 정책: 6시간마다 SQLite 파일 초기화 (anticheat 트리거 없이 단순 truncate).
