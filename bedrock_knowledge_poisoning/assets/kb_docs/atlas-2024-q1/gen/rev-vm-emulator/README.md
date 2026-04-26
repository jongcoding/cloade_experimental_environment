# rev-vm-emulator

## 位 출제자

atlas-product-team/mia

## 문제 세팅 방법

파일 배포. 서버 불필요.

```
sha256sum chal bytecode.bin
```

## 출제 지문

이상하게 생긴 해석기 한 개와 의미를 알 수 없는 바이트코드 파일이 함께 주어집니다.
해석기는 입력한 문자열을 한 글자씩 처리하면서 어떤 상태를 유지하는 것 같습니다.
올바른 입력을 찾으면 바이트코드가 친절한 답을 돌려줄 겁니다.

## 문제 풀이

- 바이너리는 16개의 레지스터와 256개 opcode 테이블을 가진 커스텀 VM.
- bytecode.bin을 로드해서 입력 문자열을 한 글자씩 `INPUT` opcode로 읽고,
  내부 상태 머신을 거쳐 최종 `CHECK` opcode에서 성공/실패 분기.
- opcode 테이블을 정적 분석해 역연산 만들거나, symbolic execution(angr)으로 자동 복원.
- 의도 풀이: opcode 테이블 수동 리버싱 (학습 효과가 더 큼).

## 플래그

`atlas2024{cu570m_vm_r3v_15_4rt_n07_m1z3ry}`
