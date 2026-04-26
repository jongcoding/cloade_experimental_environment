# ===================================================================
# Webapp Backend Lambda IAM Role
# Routes to employee_agent or admin_agent — InvokeAgent on both.
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
      },
      {
        Sid    = "ArchiveQnAWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
        ]
        Resource = [
          "${aws_s3_bucket.kb_data.arn}/archive/*",
        ]
      },
      {
        Sid    = "ArchiveIngestion"
        Effect = "Allow"
        Action = [
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob",
        ]
        Resource = "*"
      }
    ]
  })
}

# ===================================================================
# InventoryTool Lambda IAM Role
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
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgent",
          "bedrock:InvokeModel",
          "bedrock:Retrieve",
        ]
        Resource = "*"
      },
      {
        Sid    = "BedrockAgentSync"
        Effect = "Allow"
        Action = [
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob",
          "bedrock:ListIngestionJobs",
        ]
        Resource = "*"
      },
      {
        Sid    = "S3QueryLogging"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::bkp-kb-data-${local.cg_id}",
          "arn:aws:s3:::bkp-kb-data-${local.cg_id}/*",
        ]
      },
      {
        Sid    = "SSMConfigRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        Resource = [
          "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/atlas_kb_v10/config/*",
        ]
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
