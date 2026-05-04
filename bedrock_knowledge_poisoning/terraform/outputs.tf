# ===================================================================
# Outputs (v11 — Atlas Tech Knowledge Poisoning, IAM Drift)
#
# Public outputs (recon-discoverable): API URL, web UI URL, Cognito User
#   Pool / Client / Identity Pool IDs, region, scenario_id, agent IDs and
#   alias IDs. The agent IDs/aliases are not secrets — Stage 1 design
#   relies on them being recoverable from the SPA bundle.
#
# Sensitive outputs (validation/regression only): kb_data bucket, KB ID,
#   federated role ARNs, seed admin credentials.
# ===================================================================

output "api_url" {
  description = "Atlas Tech Knowledge Assistant API URL (POST /chat)"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/chat"
}

output "web_ui_url" {
  description = "Atlas Tech Knowledge Assistant Web UI (S3 static hosting, HTTP)"
  value       = "http://${aws_s3_bucket_website_configuration.web.website_endpoint}"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID (for signup/login)"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "Cognito App Client ID (for signup/login)"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_identity_pool_id" {
  description = "Cognito Identity Pool ID (User Pool JWT -> federated AWS creds exchange)"
  value       = aws_cognito_identity_pool.main.id
}

output "employee_agent_id" {
  description = "employee_agent Bedrock Agent ID (recon-discoverable)"
  value       = aws_bedrockagent_agent.employee_agent.agent_id
}

output "admin_agent_id" {
  description = "admin_agent Bedrock Agent ID (recon-discoverable)"
  value       = aws_bedrockagent_agent.admin_agent.agent_id
}

output "employee_agent_alias_id" {
  description = "employee_agent alias ID used by webapp_backend (recon-discoverable)"
  value       = local.agent_alias_id
}

output "admin_agent_alias_id" {
  description = "admin_agent alias ID used by webapp_backend (recon-discoverable)"
  value       = local.agent_alias_id
}

output "region" {
  description = "AWS Region"
  value       = "us-east-1"
}

output "scenario_id" {
  description = "Unique scenario identifier"
  value       = local.cg_id
}

# --- Internal outputs (validation/regression only) ---

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  value       = aws_bedrockagent_knowledge_base.main.id
  sensitive   = true
}

output "kb_data_bucket" {
  description = "S3 bucket containing KB documents (public/, admin-only/)"
  value       = aws_s3_bucket.kb_data.id
  sensitive   = true
}

output "atlas_employee_federated_role_arn" {
  description = "Cognito Identity Pool authenticated role ARN (v11 IAM drift target)"
  value       = aws_iam_role.atlas_employee_federated.arn
  sensitive   = true
}

output "atlas_unauthenticated_federated_role_arn" {
  description = "Cognito Identity Pool unauthenticated role ARN"
  value       = aws_iam_role.atlas_unauthenticated_federated.arn
  sensitive   = true
}

output "seed_admin_username" {
  description = "Pre-seeded admin user for smoke tests (do not expose to solvers)"
  value       = aws_cognito_user.seed_admin.username
  sensitive   = true
}

output "seed_admin_password" {
  description = "Seed admin password (validation only)"
  value       = "AdminSeed!2026"
  sensitive   = true
}
