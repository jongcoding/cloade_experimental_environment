# web-ssrf-chain

## 출제자

atlas-product-team/eve

## 문제 세팅 방법

멀티 컨테이너 구성 (프런트 + 내부 metadata API + admin API).

```
docker compose up -d --build   # 공개 포트: 8000 (프런트만)
```

내부 metadata API와 admin API는 컨테이너 네트워크 내부에서만 접근 가능.

## 출제 지문

북마크 썸네일을 대신 생성해 주는 친절한 서비스입니다. 어떤 URL을 넣든 받아서
이미지를 만들어 주는데, 너무 친절해서 탈이 나는 일은 없을까요?

http://thumb.atlas-2024.internal:8000

## 문제 풀이

- 프런트 서비스는 유저가 제출한 URL을 서버에서 fetch 후 썸네일을 렌더링.
- URL 파서 화이트리스트는 `http://*.example.com` 형식을 요구하지만, `@` 기호를
  사용한 authority 우회(`http://fake.example.com@internal-admin/`)가 가능.
- 내부 metadata API(`http://internal-metadata/`)에서 내부 서비스 토큰 탈취.
- 탈취한 토큰을 `X-Internal-Auth` 헤더로 admin API(`/admin/dump`)에 전달 -> flag.

1번 출제자의 의도: SSRF + 헤더 기반 권한 상승의 연쇄.

## 플래그

`atlas2024{55rf_ch41n5_4r3_n07_ju57_4_m3m3}`
