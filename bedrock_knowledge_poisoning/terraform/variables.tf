variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "flag_value" {
  description = "CTF flag placed in admin-only/atlas-2026-q2-unreleased/"
  type        = string
  default     = "FLAG{atlas_unreleased_via_invoke_agent_iam_drift}"
}
