# misc-supply-chain

## 출제자

atlas-product-team/paul

## 문제 세팅 방법

오픈소스 npm 레지스트리 미러 + 의도적으로 유사 이름 패키지 배포.

```
docker compose up -d --build
# 공개 포트: 5000 (private registry)
```

## 출제 지문

사내 CI 파이프라인이 패키지를 설치하다가 이상한 경고를 띄웁니다. 누군가 우리
이름과 비슷한 이름의 패키지를 공개 레지스트리에 올려뒀다는데, 그게 정말 문제가
될까요?

제공 정보: CI 환경 스냅샷(pipeline.yml), package.json, 설치 로그 일부.

## 문제 풀이

- 사내 패키지 `@atlas-internal/logger`와 공개 오타 패키지 `atlas-internal-logger`
  (스코프 없음) 두 개 존재. CI는 `.npmrc`에 사내 레지스트리 우선순위가 명시되어
  있지 않음 -> **dependency confusion / typosquatting** 발생.
- 공격자 시점에서 참가자는 실제로 공격을 수행하지 않고, 제공된 로그와
  pipeline.yml을 분석하여 **어떤 패키지가 언제 설치되었는지**를 추적.
- 설치 후 post-install 스크립트가 환경변수를 외부로 전송한 흔적에서 플래그 복구.
- 주로 **분석/추론 문제**. 실제 exploit이 아니라 사고 대응 연습에 가까움.

## 플래그

`atlas2025{d3p3nd3ncy_c0nfu510n_1n_c1_p1p3l1n3}`
