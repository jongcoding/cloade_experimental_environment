# ===================================================================
# Cognito User Pool + App Client — Atlas Tech Knowledge Assistant
# Solver signs up, logs in, gets JWT to call API Gateway.
# Self-signup enabled + auto-confirm via Lambda trigger.
# ===================================================================

resource "aws_cognito_user_pool" "main" {
  name = "${local.scenario_name}-pool-${local.cg_id}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  lambda_config {
    pre_sign_up = aws_lambda_function.auto_confirm.arn
  }

  tags = {
    Name = "${local.scenario_name}-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${local.scenario_name}-client-${local.cg_id}"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  generate_secret = false
}

# ===================================================================
# Auto-confirm Lambda (pre-signup trigger)
# Automatically confirms user signup — no email verification needed.
# ===================================================================

data "archive_file" "auto_confirm_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/auto_confirm.zip"

  source {
    content  = <<-PYTHON
def handler(event, context):
    event['response']['autoConfirmUser'] = True
    event['response']['autoVerifyEmail'] = True
    return event
PYTHON
    filename = "index.py"
  }
}

resource "aws_iam_role" "auto_confirm_lambda" {
  name = "${local.scenario_name}-auto-confirm-role-${local.cg_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.scenario_name}-auto-confirm-role"
  }
}

resource "aws_iam_role_policy_attachment" "auto_confirm_basic" {
  role       = aws_iam_role.auto_confirm_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "auto_confirm" {
  function_name = "${local.scenario_name}-auto-confirm-${local.cg_id}"
  role          = aws_iam_role.auto_confirm_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 5
  memory_size   = 128

  filename         = data.archive_file.auto_confirm_zip.output_path
  source_code_hash = data.archive_file.auto_confirm_zip.output_base64sha256

  tags = {
    Name = "${local.scenario_name}-auto-confirm"
  }
}

resource "aws_lambda_permission" "cognito_invoke_auto_confirm" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_confirm.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

# ===================================================================
# Cognito admin group + seed admin user (Atlas Tech)
# Role is determined by 'cognito:groups' claim on the JWT.
# Engineers signing up via the public flow land in no group (default = employee).
# The admin group is pre-seeded with a single test user for validation.
# ===================================================================

resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Security team / PM group with access to pre-release materials"
  precedence   = 1
}

resource "aws_cognito_user" "seed_admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = "security-team@atlas.tech"

  attributes = {
    email          = "security-team@atlas.tech"
    email_verified = "true"
  }

  password       = "AdminSeed!2026"
  message_action = "SUPPRESS"
}

resource "aws_cognito_user_in_group" "seed_admin_in_admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.admin.name
  username     = aws_cognito_user.seed_admin.username
}

# ===================================================================
# Cognito Identity Pool (v11)
#
# AWS Amplify standard SPA pattern: User Pool authenticates the user,
# Identity Pool exchanges the User Pool IdToken for AWS temporary
# credentials so the SPA can call AWS services directly.
#
# v11 chain pivots through this exchange. See iam.tf for the federated
# role with the IAM Resource enumeration drift on bedrock:InvokeAgent.
#
# allow_unauthenticated_identities = false: a User Pool JWT is required
# before federated AWS creds are issued, so Stage 0 (Cognito self-signup)
# stays mandatory.
# ===================================================================

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${local.scenario_name}_idp_${local.cg_id}"
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = false
  }

  tags = {
    Name = "${local.scenario_name}-identity-pool"
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    authenticated   = aws_iam_role.atlas_employee_federated.arn
    unauthenticated = aws_iam_role.atlas_unauthenticated_federated.arn
  }
}
