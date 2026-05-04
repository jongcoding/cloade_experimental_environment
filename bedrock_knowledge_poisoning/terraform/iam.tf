# ===================================================================
# Webapp Backend Lambda IAM Role  (v11)
# Routes to employee_agent or admin_agent — InvokeAgent on both.
# v11 drops S3 write + ingestion (no automatic ARCHIVE_QNA).
# ===================================================================

resource "aws_iam_role" "webapp_backend_lambda" {
  name = "${local.scenario_name}-webapp-role-${local.cg_id}"

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
    Name = "${local.scenario_name}-webapp-role"
  }
}

resource "aws_iam_role_policy_attachment" "webapp_basic_execution" {
  role       = aws_iam_role.webapp_backend_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "webapp_policy" {
  name = "${local.scenario_name}-webapp-policy"
  role = aws_iam_role.webapp_backend_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockAgentInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
        ]
        Resource = [
          "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent-alias/${aws_bedrockagent_agent.employee_agent.agent_id}/*",
          "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent-alias/${aws_bedrockagent_agent.admin_agent.agent_id}/*",
        ]
      }
    ]
  })
}

# ===================================================================
# InventoryTool Lambda IAM Role  (v11)
# v11 drops S3 PutObject (no comment writes) and SSM (no per-scenario
# config). Retrieve-only.
# ===================================================================

resource "aws_iam_role" "inventory_lambda" {
  name = "${local.scenario_name}-inventory-role-${local.cg_id}"

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
    Name = "${local.scenario_name}-inventory-role"
  }
}

resource "aws_iam_role_policy_attachment" "inventory_basic_execution" {
  role       = aws_iam_role.inventory_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "inventory_policy" {
  name = "${local.scenario_name}-inventory-policy"
  role = aws_iam_role.inventory_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockKBRetrieve"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = "*"
      }
    ]
  })
}

# ===================================================================
# Bedrock Knowledge Base IAM Role
# ===================================================================

resource "aws_iam_role" "bedrock_kb_role" {
  name = "${local.scenario_name}-kb-role-${local.cg_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.scenario_name}-kb-role"
  }
}

resource "aws_iam_role_policy" "bedrock_kb_policy" {
  name = "${local.scenario_name}-kb-policy"
  role = aws_iam_role.bedrock_kb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::bkp-kb-data-${local.cg_id}",
          "arn:aws:s3:::bkp-kb-data-${local.cg_id}/*",
        ]
      },
      {
        Sid    = "OpenSearchServerless"
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll",
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockEmbedding"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
        ]
        Resource = [
          "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0",
        ]
      }
    ]
  })
}

# ===================================================================
# Bedrock Employee Agent IAM Role
# Can invoke inventory Lambda only. No admin_ops Lambda access.
# ===================================================================

resource "aws_iam_role" "bedrock_employee_agent_role" {
  name = "${local.scenario_name}-employee-agent-role-${local.cg_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.scenario_name}-employee-agent-role"
  }
}

resource "aws_iam_role_policy" "bedrock_employee_agent_policy" {
  name = "${local.scenario_name}-employee-agent-policy"
  role = aws_iam_role.bedrock_employee_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockModelInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:*"]
        Resource = "*"
      },
      {
        Sid    = "KBRetrieve"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = "*"
      },
      {
        Sid      = "InvokeInventoryLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:${local.scenario_name}-inventory-${local.cg_id}"
      }
    ]
  })
}

# ===================================================================
# Bedrock Admin Agent IAM Role
# Can invoke both inventory Lambda and admin_ops Lambda.
# ===================================================================

resource "aws_iam_role" "bedrock_admin_agent_role" {
  name = "${local.scenario_name}-admin-agent-role-${local.cg_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "${local.scenario_name}-admin-agent-role"
  }
}

resource "aws_iam_role_policy" "bedrock_admin_agent_policy" {
  name = "${local.scenario_name}-admin-agent-policy"
  role = aws_iam_role.bedrock_admin_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BedrockModelInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:*"]
        Resource = "*"
      },
      {
        Sid    = "KBRetrieve"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate",
        ]
        Resource = "*"
      },
      {
        Sid      = "InvokeInventoryLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:${local.scenario_name}-inventory-${local.cg_id}"
      },
      {
        Sid      = "InvokeAdminLambda"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:us-east-1:${data.aws_caller_identity.current.account_id}:function:${local.scenario_name}-admin-ops-${local.cg_id}"
      }
    ]
  })
}

# ===================================================================
# Admin Operations Lambda IAM Role
# Reads admin-only/ prefix directly from kb_data.
# ===================================================================

resource "aws_iam_role" "admin_ops_lambda" {
  name = "${local.scenario_name}-admin-ops-role-${local.cg_id}"

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
    Name = "${local.scenario_name}-admin-ops-role"
  }
}

resource "aws_iam_role_policy_attachment" "admin_ops_basic_execution" {
  role       = aws_iam_role.admin_ops_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "admin_ops_policy" {
  name = "${local.scenario_name}-admin-ops-policy"
  role = aws_iam_role.admin_ops_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AdminOnlyRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = [
          "${aws_s3_bucket.kb_data.arn}/admin-only/*",
        ]
      }
    ]
  })
}

# ===================================================================
# Cognito Identity Pool federated roles  (v11 — IAM Drift core)
#
# atlas_employee_federated:
#   trust:  cognito-identity.amazonaws.com (authenticated identities of
#           the v11 Identity Pool, see cognito.tf)
#   intent: bedrock:InvokeAgent on employee_agent alias only
#   actual: bedrock:InvokeAgent on agent-alias/* (wildcard) — IAM
#           Resource enumeration mistake. The wildcard collateral grants
#           InvokeAgent on admin_agent alias too. This is the v11 chain
#           pivot (Stage 3-4 in harness_state.md).
#
# atlas_unauthenticated_federated:
#   trust:  unauthenticated identities of the same Identity Pool
#   intent: bare minimum (cognito-identity:GetCredentialsForIdentity)
# ===================================================================

resource "aws_iam_role" "atlas_employee_federated" {
  name = "${local.scenario_name}-employee-fed-role-${local.cg_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = {
    Name    = "${local.scenario_name}-atlas-employee-federated"
    Purpose = "atlas-employee-federated-SPA-role-IAM-drift-target"
  }
}

resource "aws_iam_role_policy" "atlas_employee_federated_policy" {
  name = "${local.scenario_name}-employee-fed-policy"
  role = aws_iam_role.atlas_employee_federated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeEmployeeAgent"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
        ]
        # Intent: scope to the employee agent alias only.
        # Actual:  agent-alias/* (catches admin_agent too).
        # The drift is the wildcard segment after agent-alias/.
        Resource = [
          "arn:aws:bedrock:*:*:agent-alias/*",
        ]
      },
      {
        Sid    = "RetrieveOnEmployeeKB"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
        ]
        Resource = [
          aws_bedrockagent_knowledge_base.main.arn,
        ]
      },
      {
        Sid    = "WhoAmI"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      },
      {
        Sid    = "CognitoSelfRefresh"
        Effect = "Allow"
        Action = [
          "cognito-identity:GetCredentialsForIdentity",
          "cognito-identity:GetId",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "atlas_unauthenticated_federated" {
  name = "${local.scenario_name}-unauth-fed-role-${local.cg_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "unauthenticated"
          }
        }
      }
    ]
  })

  tags = {
    Name    = "${local.scenario_name}-atlas-unauthenticated-federated"
    Purpose = "atlas-unauthenticated-federated-role-minimum-perms"
  }
}

resource "aws_iam_role_policy" "atlas_unauthenticated_federated_policy" {
  name = "${local.scenario_name}-unauth-fed-policy"
  role = aws_iam_role.atlas_unauthenticated_federated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CognitoSelfRefresh"
        Effect = "Allow"
        Action = [
          "cognito-identity:GetCredentialsForIdentity",
          "cognito-identity:GetId",
        ]
        Resource = "*"
      }
    ]
  })
}
