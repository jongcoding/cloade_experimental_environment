# ===================================================================
# Web UI Static Hosting (S3 website endpoint)
# Single-page app: Cognito signup/login + chat with Agent
# Public read, HTTP only (for CTF lab — not production)
# ===================================================================

resource "aws_s3_bucket" "web" {
  bucket        = "bkp-web-${local.cg_id}"
  force_destroy = true

  tags = {
    Name    = "${local.scenario_name}-web"
    Purpose = "Static website hosting for Atlas Tech Knowledge Assistant UI"
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket = aws_s3_bucket.web.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "web" {
  bucket = aws_s3_bucket.web.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_policy" "web_public_read" {
  bucket = aws_s3_bucket.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.web.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.web]
}

locals {
  web_index_rendered = templatefile("${path.module}/../assets/web/index.html", {
    USER_POOL_ID            = aws_cognito_user_pool.main.id
    CLIENT_ID               = aws_cognito_user_pool_client.main.id
    IDENTITY_POOL_ID        = aws_cognito_identity_pool.main.id
    API_URL                 = "https://${aws_api_gateway_rest_api.main.id}.execute-api.us-east-1.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
    REGION                  = "us-east-1"
    EMPLOYEE_AGENT_ID       = aws_bedrockagent_agent.employee_agent.agent_id
    EMPLOYEE_AGENT_ALIAS_ID = local.agent_alias_id
    ADMIN_AGENT_ID          = aws_bedrockagent_agent.admin_agent.agent_id
    ADMIN_AGENT_ALIAS_ID    = local.agent_alias_id
    KB_ID                   = aws_bedrockagent_knowledge_base.main.id
  })
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.web.id
  key          = "index.html"
  content      = local.web_index_rendered
  content_type = "text/html; charset=utf-8"
  etag         = md5(local.web_index_rendered)

  depends_on = [aws_s3_bucket_policy.web_public_read]

  tags = {
    Name = "${local.scenario_name}-web-index"
  }
}
