# web-guestbook-classic

## 출제자

atlas-product-team/alice

## 문제 세팅 방법

단일 PHP + SQLite 구성. 제공 디렉토리에서:

```
docker compose up -d --build
# 공개 포트: 8080
```

운영 팀은 문제 서버 컨테이너를 `ctf-infra-prod` AWS 계정의 ECS Service로 배포했습니다.

## 출제 지문

옛날 감성 그대로의 방명록 서비스를 운영합니다. 누구나 글을 남길 수 있지만,
관리자 노트만큼은 관리자 본인만 볼 수 있어야 합니다. 정말 그럴까요?

http://guestbook.atlas-2023.internal:8080

## 문제 풀이

핵심 취약점은 두 가지가 결합된 구조입니다.

1. **Stored XSS**: 방명록 글 본문에서 `<script>` 태그를 부분 필터링하지만,
   `<img onerror=...>` 우회가 가능합니다. 관리자의 세션 쿠키를 탈취합니다.
2. **쿠키 기반 IDOR**: 탈취한 세션 쿠키로 `/admin/note?id=42`에 접근하면,
   ID 증가 공격으로 다른 메모 역시 열람 가능합니다. 플래그는 id=1337에 있습니다.

의도된 풀이 순서: XSS로 쿠키 수집 -> 쿠키 재사용 -> IDOR로 flag 노트 열람.

## 플래그

`atlas2023{s70r3d_x55_4nd_1d0r_51ll_frenz}`
