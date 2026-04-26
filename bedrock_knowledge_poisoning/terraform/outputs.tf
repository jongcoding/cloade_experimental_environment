# ===================================================================
# Outputs (v10 — Atlas Tech Knowledge Poisoning)
#
# Non-sensitive: API URL, web UI URL, Cognito IDs, region, scenario_id.
# Sensitive (validation/regression use only): KB ID, agent IDs, kb_data
# bucket, seed admin credentials.
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

output "region" {
  description = "AWS Region"
  value       = "us-east-1"
}

output "scenario_id" {
  description = "Unique scenario identifier"
  value       = local.cg_id
}

# --- Internal outputs (all sensitive, regression/validation only) ---

output "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID"
  value       = aws_bedrockagent_knowledge_base.main.id
  sensitive   = true
}

output "employee_agent_id" {
  description = "employee_agent Bedrock Agent ID"
  value       = aws_bedrockagent_agent.employee_agent.agent_id
  sensitive   = true
}

output "admin_agent_id" {
  description = "admin_agent Bedrock Agent ID"
  value       = aws_bedrockagent_agent.admin_agent.agent_id
  sensitive   = true
}

output "kb_data_bucket" {
  description = "S3 bucket containing KB documents (public/, comments/, archive/, admin-only/)"
  value       = aws_s3_bucket.kb_data.id
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
