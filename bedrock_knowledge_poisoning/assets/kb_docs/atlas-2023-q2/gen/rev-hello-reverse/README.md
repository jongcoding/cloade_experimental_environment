# rev-hello-reverse

## 출제자

atlas-product-team/carol

## 문제 세팅 방법

파일 배포만. 서버 불필요.

```
sha256sum hello_reverse  # 배포 전 해시 확인
```

## 출제 지문

"hello"라고 말하면 비밀을 알려주겠다고 합니다. 그런데 "hello"가 정확히 어떤
문자열을 의미하는 걸까요? 입력 문자열이 맞으면 그대로 출력되는 것 같습니다.

## 문제 풀이

- 64-bit ELF, stripped, UPX 패킹 **아님** (의외로 평문).
- 입력 문자열을 XOR 0x42 한 뒤 상수 배열과 비교.
- Ghidra나 IDA로 `main` 흐름만 따라가면 상수 배열을 바로 읽을 수 있음.
- 배열 역산하면 입력해야 할 문자열이 나오고, 그 문자열이 곧 플래그.

## 플래그

`atlas2023{x0r_0f_042_15_n07_encryp710n}`
