---
name: novel-discovery
description: >-
  기존 CloudGoat에 없는 새 공격 벡터를 탐색. 체인에 넣을 기법이 부족하거나
  신규 AWS 서비스의 공격 표면이 필요할 때 사용.
  Use when looking for novel attack vectors, exploring new AWS services,
  or testing boundary conditions of known techniques.
argument-hint: "[탐색 전략: service/boundary/error/cloudtrail]"
disable-model-invocation: true
allowed-tools: Bash(terraform *) Bash(aws *)
---

# 미지 영역 탐색 (Novel Discovery)

탐색 전략: $ARGUMENTS

## 전략 1: 새로운 AWS 서비스 공격 표면

1. IAM 액션 열거 (읽기/변경/실행/위험 분류)
2. Trust Policy 분석 (Service Principal, Identity Confusion 가능성)
3. 자격증명 전달 경로 (IMDS? Container Creds? 환경변수?)
4. 유망한 벡터 1-2개 실험 (최소 Terraform -> 배포 -> 공격 -> 결과)

## 전략 2: 알려진 기법의 경계 조건

1. 조건 완화 실험: 필수 조건 없어도 작동하는가?
2. 조건 우회 실험: 다른 서비스 경유로 우회 가능한가?
3. 조건 조합 실험: 약한 조건 여러 개 조합으로 작동하는가?
4. 시간/순서 실험: Eventually Consistent 활용 가능한가?

## 전략 3: 에러 메시지 기반 정보 추출

- 존재/비존재 리소스 에러 차이로 열거
- 권한 부족 에러에서 ARN/계정ID 노출
- 조건부 정책 에러에서 조건 정보 노출

## 전략 4: CloudTrail 역방향 설계

- 정상 운영 로그에서 공격 가능한 API 발견
- 정상 트래픽처럼 보이는 공격 설계

## 결과 종합

1. 유망한 공격 벡터 Top 3
2. 추가 실험 필요한 영역 Top 3
3. 기존 CloudGoat에 없는 조합 제안
4. 다음 세션에서 할 것

---

유망한 벡터를 발견하면 복귀:
- **멀티에이전트**: `/orchestrate [코드네임] [벡터]를 Stage로 구현` (권장)
- **싱글에이전트**: `/harness-loop [코드네임]`

> **팁**: `/orchestrate`에서 Recon Scout 에이전트가 이 스킬의 역할을 수행한다.
> 단독 탐색이 필요할 때만 이 스킬을 직접 사용해라.
