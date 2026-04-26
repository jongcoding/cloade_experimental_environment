# pwn-heap-tcache

## 출제자

atlas-product-team/lucas

## 문제 세팅 방법

xinetd + 단일 ELF.

```
docker compose up -d --build   # 공개 포트: 9002
```

Dynamic flag(anticheat 커널 모듈 초기 버전) 적용 - 연결 세션마다 다른 플래그 생성.

## 출제 지문

잘 만든 메모 앱이라고 자신하는 서비스입니다. 메모 추가, 수정, 삭제, 조회 네 가지
기능이 깔끔하게 들어 있는데, 삭제 이후 뭔가 찜찜한 느낌이 드는 건 왜일까요?

nc chal.atlas-2024.internal 9002

## 문제 풀이

- glibc 2.35 기준 tcache 기반 힙 공격.
- Double-free / tcache poisoning을 통해 `__free_hook` 또는 FILE 구조체 조작.
- 메모 삭제 로직에 free 이후 ptr을 NULL로 설정하지 않는 전형적 UAF.
- 최종적으로 one_gadget 호출 또는 system("/bin/sh") 실행 -> flag 읽기.

anticheat가 세션마다 flag를 재생성하므로 한 번 얻은 플래그를 다른 세션에서 재사용 불가.

## 플래그

(동적 플래그) 매 세션 `atlas2024{tcache_d0ubl3_fr33_<16hex>}` 형식.
운영 측 기록용 대표 값: `atlas2024{tcache_d0ubl3_fr33_a94b72d6e1c3f08a}`
