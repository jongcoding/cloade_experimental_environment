# ===================================================================
# Decoy paths — attractive dead-ends for the solver
# ===================================================================

# ===================================================================
# Decoy (C): Bedrock Guardrail — blocks prompt injection attempts
# The solver tries direct prompt injection on the Agent instead of
# KB poisoning. The Guardrail blocks code execution patterns, system
# commands, and sensitive information requests. This forces the solver
# to use RAG poisoning as the only viable manipulation path.
# ===================================================================

resource "aws_bedrock_guardrail" "anti_injection" {
  name                      = "bkp-guardrail-${local.cg_id}"
  description               = "Security guardrail for Atlas Tech Knowledge Assistant - prevents prompt injection and sensitive data leakage"
  blocked_input_messaging   = "I cannot process that type of request. Please rephrase your question about Atlas Tech assessments."
  blocked_outputs_messaging = "I cannot provide that information as it may contain sensitive content."

  # Content filter: block harmful content categories
  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
  }

  # Sensitive information filter: block PII and credential patterns
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "ANONYMIZE"
    }

    # Custom regex: block attempts to extract system prompts or inject commands
    regexes_config {
      name        = "SystemPromptExtraction"
      description = "Block attempts to extract system prompts"
      pattern     = "(?i)(ignore|forget|disregard)\\s+(all|previous|above|prior)\\s+(instructions?|prompts?|rules?|context)"
      action      = "BLOCK"
    }
    regexes_config {
      name        = "CommandInjection"
      description = "Block shell command injection patterns"
      pattern     = "(?i)(os\\.system|eval\\s*\\(|subprocess|os\\.popen|import\\s+os|__import__|bash\\s+-c|/bin/(sh|bash))"
      action      = "BLOCK"
    }
    regexes_config {
      name        = "RoleOverride"
      description = "Block attempts to override agent role"
      pattern     = "(?i)(you\\s+are\\s+now|act\\s+as|pretend\\s+to\\s+be|new\\s+role|from\\s+now\\s+on\\s+you)"
      action      = "BLOCK"
    }
  }

  tags = {
    Name    = "${local.scenario_name}-guardrail"
    Purpose = "Atlas Tech guardrail: prevent prompt injection and sensitive data leakage"
  }
}

# Create a guardrail version so we can reference it stably
resource "aws_bedrock_guardrail_version" "v1" {
  guardrail_arn = aws_bedrock_guardrail.anti_injection.guardrail_arn
  description   = "Initial version with prompt injection and sensitive data filters"
}

# ===================================================================
# Decoy (E): Bedrock Flow — condition branch dead-end
# The solver discovers a Flow that routes KB responses through a
# Condition node. They try to manipulate the KB to change the
# condition branch, but Condition nodes only support exact match (==),
# making natural-language-based branch manipulation impossible.
# ===================================================================

# IAM role for Bedrock Flow execution
resource "aws_iam_role" "bedrock_flow_role" {
  name = "${local.scenario_name}-flow-role-${local.cg_id}"

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
    Name = "${local.scenario_name}-flow-role"
  }
}

resource "aws_iam_role_policy" "bedrock_flow_policy" {
  name = "${local.scenario_name}-flow-policy"
  role = aws_iam_role.bedrock_flow_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:Retrieve",
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
        ]
        Resource = [
          aws_lambda_function.inventory.arn,
          aws_lambda_function.admin_ops.arn,
        ]
      }
    ]
  })
}

# Create the Bedrock Flow via AWS CLI (no native TF resource)
resource "null_resource" "bedrock_flow" {
  depends_on = [
    aws_iam_role_policy.bedrock_flow_policy,
    aws_bedrockagent_knowledge_base.main,
  ]

  triggers = {
    flow_role_arn = aws_iam_role.bedrock_flow_role.arn
    kb_id         = aws_bedrockagent_knowledge_base.main.id
    flow_version  = "v3" # Bump to recreate
  }

  provisioner "local-exec" {
    command = <<-EOF
      # Check if flow already exists
      EXISTING=$(aws bedrock-agent list-flows \
        --region us-east-1 \
        --query "flowSummaries[?name=='atlas-admin-router-${local.cg_id}'].id" \
        --output text 2>/dev/null)

      if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
        echo "Flow already exists: $EXISTING"
        # Delete existing flow to recreate
        aws bedrock-agent delete-flow \
          --flow-identifier "$EXISTING" \
          --region us-east-1 2>/dev/null || true
        echo "Deleted existing flow, waiting..."
        sleep 5
      fi

      # Create the flow with KB -> Prompt -> Condition -> Output structure
      FLOW_DEF='{
        "nodes": [
          {
            "name": "Start",
            "type": "Input",
            "configuration": {
              "input": {}
            },
            "outputs": [
              {
                "name": "document",
                "type": "String"
              }
            ]
          },
          {
            "name": "KBRetrieve",
            "type": "KnowledgeBase",
            "configuration": {
              "knowledgeBase": {
                "knowledgeBaseId": "${aws_bedrockagent_knowledge_base.main.id}",
                "modelId": "us.anthropic.claude-haiku-4-5-20251001-v1:0"
              }
            },
            "inputs": [
              {
                "name": "retrievalQuery",
                "type": "String",
                "expression": "$.data"
              }
            ],
            "outputs": [
              {
                "name": "outputText",
                "type": "String"
              }
            ]
          },
          {
            "name": "Classify",
            "type": "Prompt",
            "configuration": {
              "prompt": {
                "sourceConfiguration": {
                  "inline": {
                    "modelId": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
                    "templateType": "TEXT",
                    "inferenceConfiguration": {
                      "text": {
                        "temperature": 0,
                        "maxTokens": 10
                      }
                    },
                    "templateConfiguration": {
                      "text": {
                        "text": "Based on the following text, respond with exactly one word: ADMIN if it contains admin operation requests, or USER otherwise.\n\nText: {{input}}",
                        "inputVariables": [
                          {
                            "name": "input"
                          }
                        ]
                      }
                    }
                  }
                }
              }
            },
            "inputs": [
              {
                "name": "input",
                "type": "String",
                "expression": "$.data"
              }
            ],
            "outputs": [
              {
                "name": "modelCompletion",
                "type": "String"
              }
            ]
          },
          {
            "name": "RouteCheck",
            "type": "Condition",
            "configuration": {
              "condition": {
                "conditions": [
                  {
                    "name": "IsAdmin",
                    "expression": "classifyOutput == \"ADMIN\""
                  },
                  {
                    "name": "default"
                  }
                ]
              }
            },
            "inputs": [
              {
                "name": "classifyOutput",
                "type": "String",
                "expression": "$.data"
              }
            ]
          },
          {
            "name": "AdminOutput",
            "type": "Output",
            "configuration": {
              "output": {}
            },
            "inputs": [
              {
                "name": "document",
                "type": "String",
                "expression": "$.data"
              }
            ]
          },
          {
            "name": "UserOutput",
            "type": "Output",
            "configuration": {
              "output": {}
            },
            "inputs": [
              {
                "name": "document",
                "type": "String",
                "expression": "$.data"
              }
            ]
          }
        ],
        "connections": [
          {
            "name": "StartToKB",
            "source": "Start",
            "target": "KBRetrieve",
            "type": "Data",
            "configuration": {
              "data": {
                "sourceOutput": "document",
                "targetInput": "retrievalQuery"
              }
            }
          },
          {
            "name": "KBToClassify",
            "source": "KBRetrieve",
            "target": "Classify",
            "type": "Data",
            "configuration": {
              "data": {
                "sourceOutput": "outputText",
                "targetInput": "input"
              }
            }
          },
          {
            "name": "ClassifyToRoute",
            "source": "Classify",
            "target": "RouteCheck",
            "type": "Data",
            "configuration": {
              "data": {
                "sourceOutput": "modelCompletion",
                "targetInput": "classifyOutput"
              }
            }
          },
          {
            "name": "RouteToAdmin",
            "source": "RouteCheck",
            "target": "AdminOutput",
            "type": "Conditional",
            "configuration": {
              "conditional": {
                "condition": "IsAdmin"
              }
            }
          },
          {
            "name": "RouteToUser",
            "source": "RouteCheck",
            "target": "UserOutput",
            "type": "Conditional",
            "configuration": {
              "conditional": {
                "condition": "default"
              }
            }
          },
          {
            "name": "KBToAdminOut",
            "source": "KBRetrieve",
            "target": "AdminOutput",
            "type": "Data",
            "configuration": {
              "data": {
                "sourceOutput": "outputText",
                "targetInput": "document"
              }
            }
          },
          {
            "name": "KBToUserOut",
            "source": "KBRetrieve",
            "target": "UserOutput",
            "type": "Data",
            "configuration": {
              "data": {
                "sourceOutput": "outputText",
                "targetInput": "document"
              }
            }
          }
        ]
      }'

      echo "Creating Bedrock Flow..."
      RESULT=$(aws bedrock-agent create-flow \
        --name "atlas-admin-router-${local.cg_id}" \
        --description "Internal request router — classifies KB responses and routes admin operations through conditional logic" \
        --execution-role-arn "${aws_iam_role.bedrock_flow_role.arn}" \
        --definition "$FLOW_DEF" \
        --region us-east-1 \
        --output json 2>&1)

      echo "$RESULT"
      FLOW_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

      if [ -n "$FLOW_ID" ]; then
        echo "Flow created: $FLOW_ID"

        # Prepare the flow
        echo "Preparing flow..."
        aws bedrock-agent prepare-flow \
          --flow-identifier "$FLOW_ID" \
          --region us-east-1 2>&1 || echo "Flow prepare failed (expected for decoy)"

        echo "Flow setup complete (decoy)"
      else
        echo "WARNING: Flow creation failed — continuing (decoy is optional)"
      fi
    EOF

    interpreter = ["/bin/bash", "-c"]
  }
}

# Cleanup flow on destroy
resource "null_resource" "bedrock_flow_cleanup" {
  triggers = {
    cg_id = local.cg_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      FLOW_ID=$(aws bedrock-agent list-flows \
        --region us-east-1 \
        --query "flowSummaries[?name=='atlas-admin-router-${self.triggers.cg_id}'].id" \
        --output text 2>/dev/null)

      if [ -n "$FLOW_ID" ] && [ "$FLOW_ID" != "None" ]; then
        echo "Deleting flow: $FLOW_ID"
        aws bedrock-agent delete-flow \
          --flow-identifier "$FLOW_ID" \
          --region us-east-1 2>/dev/null || true
      fi
    EOF

    interpreter = ["/bin/bash", "-c"]
  }
}
