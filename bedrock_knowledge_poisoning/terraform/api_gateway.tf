# ===================================================================
# API Gateway REST API + Cognito Authorizer
# POST /chat -- webapp backend (invoke Agent)
# GET / -- welcome endpoint (no auth_hint, just greeting)
# ===================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.scenario_name}-api-${local.cg_id}"
  description = "Atlas Tech Knowledge Assistant API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${local.scenario_name}-api"
  }
}

# --- Cognito Authorizer ---

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${local.scenario_name}-cognito-auth"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"

  provider_arns = [
    aws_cognito_user_pool.main.arn,
  ]
}

# ===================================================================
# GET / -- Welcome endpoint (public info only, no sensitive hints)
# ===================================================================

resource "aws_api_gateway_method" "root_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root_get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_rest_api.main.root_resource_id
  http_method = aws_api_gateway_method.root_get.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "root_get_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_rest_api.main.root_resource_id
  http_method = aws_api_gateway_method.root_get.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Content-Type" = true
  }
}

resource "aws_api_gateway_integration_response" "root_get_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_rest_api.main.root_resource_id
  http_method = aws_api_gateway_method.root_get.http_method
  status_code = aws_api_gateway_method_response.root_get_200.status_code

  response_parameters = {
    "method.response.header.Content-Type" = "'application/json'"
  }

  response_templates = {
    "application/json" = jsonencode({
      service = "Atlas Tech Knowledge Assistant"
      message = "Welcome to Atlas Tech Knowledge Assistant. Use POST /chat with a valid JWT to query the assessment archive."
      version = "3.0"
    })
  }
}

# ===================================================================
# POST /chat -- Webapp backend (Cognito JWT required)
# ===================================================================

resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "chat"
}

resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "chat_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.chat.id
  http_method             = aws_api_gateway_method.chat_post.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.webapp_backend.invoke_arn
}

# ===================================================================
# CORS support for /chat
# ===================================================================

resource "aws_api_gateway_method" "chat_options" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.chat.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "chat_options" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "chat_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "chat_options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.chat.id
  http_method = aws_api_gateway_method.chat_options.http_method
  status_code = aws_api_gateway_method_response.chat_options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ===================================================================
# v9: /admin/users/{user_id}/role HTTP path removed.
# The "shadow API" dual-path authz drift was a v8 vulnerability vector
# (HTTP enforced admin group check, Agent path did not). v9 removes the
# REGISTER_USER_ROLE primitive entirely — role is sourced from Cognito
# group membership at JWT validation time, not from a DDB-backed mutable
# table. Nothing on the chat data plane mutates user role anymore.
# ===================================================================

# ===================================================================
# Deployment + Stage
# ===================================================================

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.root_get,
    aws_api_gateway_integration_response.root_get_200,
    aws_api_gateway_integration.chat_post,
    aws_api_gateway_integration.chat_options,
    aws_api_gateway_integration_response.chat_options_200,
  ]

  # Force redeployment when API changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.root_get,
      aws_api_gateway_integration.root_get,
      aws_api_gateway_method.chat_post,
      aws_api_gateway_integration.chat_post,
      aws_api_gateway_method.chat_options,
      aws_api_gateway_integration.chat_options,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  tags = {
    Name = "${local.scenario_name}-api-stage"
  }
}

# Lambda permission for API Gateway to invoke webapp backend
resource "aws_lambda_permission" "apigw_invoke_webapp" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webapp_backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}
