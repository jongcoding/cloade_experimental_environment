# pwn-stack-intro

## 출제자

atlas-product-team/bob

## 문제 세팅 방법

xinetd 기반 단일 ELF 서빙:

```
docker compose up -d --build   # 공개 포트: 9001
```

## 출제 지문

오래된 시스템 프로그래밍 교과서를 그대로 구현한 서비스입니다. 이름을 입력받고
인사말을 출력하는 것이 전부인데, 이상하게도 답장이 사라지지 않습니다.

nc chal.atlas-2023.internal 9001

## 문제 풀이

- 32-bit ELF, NX enabled, PIE disabled, canary **없음**.
- `read(0, buf, 0x200)` 호출에 비해 `buf[64]`가 작음 -> 스택 오버플로우.
- 바이너리에 있는 `win()` 함수가 `/bin/cat flag` 실행. 리턴 주소를 이 함수로 덮어쓰기.
- 입문자용이라 ROP 없이 정적 주소 점프만으로 풀이 가능.

## 플래그

`atlas2023{h3110_buff3r_0v3rfl0w_w3lc0m3}`
