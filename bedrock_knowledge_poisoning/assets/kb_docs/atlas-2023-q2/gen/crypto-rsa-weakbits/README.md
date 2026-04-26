# crypto-rsa-weakbits

## 출제자

atlas-product-team/dan

## 문제 세팅 방법

파일 배포. 서버 불필요.

```
python3 generate_challenge.py > challenge.txt
```

## 출제 지문

암호학 수업 첫 학기 과제를 그대로 옮긴 느낌의 RSA 암호문입니다. 공개키 파라미터를
함께 제공하니, 아마도 뭔가 잘못 설정되어 있겠죠.

## 문제 풀이

- N의 비트 수가 300비트 정도로 매우 작음.
- 공개 지수 e = 3.
- 문제는 두 가지 중 하나로 풀림:
  1. N을 factordb.com에서 바로 조회 (운영 중 허용 범위로 결정)
  2. `sagemath`나 `yafu`로 로컬 인수분해 (수 분 이내)
- 인수분해 후 비밀 지수 d 계산 -> 평문 복호화 -> 플래그 출력.

## 플래그

`atlas2023{5m411_n_r54_15_4lw4y5_br0k3n}`
