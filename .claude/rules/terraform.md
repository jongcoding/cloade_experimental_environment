---
paths:
  - "**/*.tf"
  - "**/terraform/**"
---

# Terraform 작성 규칙

## 필수 태그

모든 리소스에 시나리오 식별 태그를 달아라:

```hcl
locals {
  scenario_name = "scenario_name"
  cg_id         = random_id.cg_id.hex
  default_tags = {
    Scenario  = local.scenario_name
    CgId      = local.cg_id
    ManagedBy = "terraform"
  }
}
```

## Flag 배치

- Flag는 마지막 단계에서만 접근 가능한 위치에 배치
- 형식: `FLAG{descriptive_message_about_vulnerability}`

## S3 버킷

- `force_destroy = true` 설정 필수

## 리전

- `us-east-1` 고정 (달리 지시하지 않는 한)

## 비용

- 시간당 $2 이하 유지
- 고비용 서비스 사전 경고: EKS($0.10/hr), NAT Gateway($0.045/hr), RDS Multi-AZ, OpenSearch
