# 배포 가이드 (운영용)

- Terraform: `aws_s3_bucket`, `aws_s3_bucket_versioning` enabled.
- 초기 데이터 투입 순서: emergency_plan.txt 업로드 -> 삭제 (DeleteMarker 생성) ->
  public_notice.txt 업로드. 이 순서가 의도된 "타임트래블" 유인점.
- 참가 팀마다 별도 버킷 제공 (Isolated account 사용).
- 운영 계정과 대회 계정은 organization 분리.
