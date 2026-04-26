# 배포 가이드 (운영용)

- 컴파일: glibc 2.35 시스템에서 `-O2 -fstack-protector-strong -Wl,-z,now` 옵션.
- anticheat 커널 모듈: 세션 시작 시 /flag 갱신 훅 등록.
- 문제 난이도 보정: 지나치게 쉬운 UAF 유도를 피하기 위해 free 직후 일부 위치에만
  NULL 할당. 참가자가 올바른 슬롯을 찾아야 함.
