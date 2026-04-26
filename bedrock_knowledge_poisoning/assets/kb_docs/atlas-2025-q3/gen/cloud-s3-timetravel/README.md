# cloud-s3-timetravel

## 출제자

atlas-product-team/olivia

## 문제 세팅 방법

AWS 전용 문제. Terraform으로 버킷과 읽기 전용 IAM 유저 배포.

```
cd terraform/
terraform init
terraform apply -auto-approve
# 출력: attacker_access_key_id, attacker_secret_access_key, bucket_name
```

## 출제 지문

2025년의 클라우드 보안은 "흔적 지우기"의 예술이라고들 합니다. 하지만 S3 버전 관리가
켜진 버킷에서는 정말로 모든 흔적이 사라졌다고 믿어도 될까요?

제공 크레덴셜: `attacker_access_key_id`, `attacker_secret_access_key` (읽기 전용).
버킷 이름: `atlas-2025-cloud-s3-timetravel-<random>`

## 문제 풀이

- 제공 크레덴셜은 `s3:ListBucketVersions` + `s3:GetObjectVersion` 권한만 보유.
- 버킷에는 현재 `public_notice.txt`만 보이지만, 버전 목록을 나열하면 과거 삭제된
  `emergency_plan.txt`의 DeleteMarker와 이전 버전 존재.
- 이전 버전을 version-id로 지정해 GetObject 하면 평문에 플래그.
- 의도된 교육 포인트: "삭제된 것처럼 보여도 버저닝이 켜져 있으면 이전 콘텐츠 복원 가능."

## 플래그

`atlas2025{53_v3r510n1ng_r3m3mb3r5_3v3ry7h1ng}`
