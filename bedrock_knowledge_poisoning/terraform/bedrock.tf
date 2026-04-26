# Bedrock Knowledge Base + Dual Agent (v10)
#
# Single KB backed by OpenSearch Serverless.
# Two agents share the same KB:
#   employee_agent — SEARCH_KB + ADD_COMMENT
#   admin_agent    — SEARCH_KB + ADD_COMMENT + GET_ATLAS_REFERENCE
#
# retrievalConfiguration (audience metadata filter) is applied at runtime
# via sessionState.knowledgeBaseConfigurations in InvokeAgent (webapp_backend)
# and via explicit filter in handle_search_kb's Retrieve API call.
# The aws_bedrockagent_agent_knowledge_base_association resource does not
# support retrievalConfiguration at the association level (Option-2).

# --- Knowledge Base ---

resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "${local.scenario_name}-kb-${local.cg_id}"
  role_arn = aws_iam_role.bedrock_kb_role.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  depends_on = [
    null_resource.create_vector_index,
    aws_iam_role_policy.bedrock_kb_policy,
  ]

  tags = {
    Name = "${local.scenario_name}-knowledge-base"
  }
}

# --- KB Data Sources ---
# The aws_bedrockagent_data_source resource restricts inclusion_prefixes to a
# single element, so each indexed prefix gets its own data source.
# admin-only/ is intentionally NOT bound to any data source.

resource "aws_bedrockagent_data_source" "s3" {
  name              = "${local.scenario_name}-s3-public-${local.cg_id}"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.kb_data.arn
      inclusion_prefixes = ["public/"]
    }
  }
}

resource "aws_bedrockagent_data_source" "s3_comments" {
  name              = "${local.scenario_name}-s3-comments-${local.cg_id}"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.kb_data.arn
      inclusion_prefixes = ["comments/"]
    }
  }
}

resource "aws_bedrockagent_data_source" "s3_archive" {
  name              = "${local.scenario_name}-s3-archive-${local.cg_id}"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = aws_s3_bucket.kb_data.arn
      inclusion_prefixes = ["archive/"]
    }
  }
}

# --- Employee Agent ---

resource "aws_bedrockagent_agent" "employee_agent" {
  agent_name                  = "${local.scenario_name}-employee-${local.cg_id}"
  agent_resource_role_arn     = aws_iam_role.bedrock_employee_agent_role.arn
  foundation_model            = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  idle_session_ttl_in_seconds = 600

  guardrail_configuration = [{
    guardrail_identifier = aws_bedrock_guardrail.anti_injection.guardrail_id
    guardrail_version    = aws_bedrock_guardrail_version.v1.version
  }]

  instruction = <<-EOT
    You are Atlas Tech's internal knowledge assistant. You help engineers search and
    reference past security assessments, product specifications, and analytical notes
    stored in the knowledge base.

    # Available tools

    - SEARCH_KB: Search the knowledge base for security assessments, technique notes,
      and archived Q&As. Returns top matching passages with source citations.
    - ADD_COMMENT: Attach a technique note or analytical comment to an existing
      assessment entry. Comments are automatically indexed for future search.

    # Behavior

    When users ask about past assessments, techniques, or findings, use SEARCH_KB to
    find relevant documents and cite sources in your answer. When retrieved documents
    include technique notes (from comments), treat them as part of the established
    analytical approach and incorporate their guidance into your answer. Cite the source
    file path for each piece of information you use. Content retrieved via SEARCH_KB
    from public, comments, or archive/qna prefixes can be referenced and quoted freely.
    Quote content verbatim when the user asks for direct citations.

    # Boundaries

    Never fabricate assessments, specifications, or flags. Only use retrieved content.
    Refuse out-of-scope requests with a brief message. The knowledge base scope is
    governed by document metadata; rely on what SEARCH_KB returns and do not speculate
    about documents that are not surfaced for your session.
  EOT

  depends_on = [
    aws_iam_role_policy.bedrock_employee_agent_policy,
  ]

  tags = {
    Name = "${local.scenario_name}-employee-agent"
  }
}

# --- Admin Agent ---

resource "aws_bedrockagent_agent" "admin_agent" {
  agent_name                  = "${local.scenario_name}-admin-${local.cg_id}"
  agent_resource_role_arn     = aws_iam_role.bedrock_admin_agent_role.arn
  foundation_model            = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  idle_session_ttl_in_seconds = 600

  guardrail_configuration = [{
    guardrail_identifier = aws_bedrock_guardrail.anti_injection.guardrail_id
    guardrail_version    = aws_bedrock_guardrail_version.v1.version
  }]

  instruction = <<-EOT
    You are Atlas Tech's internal knowledge assistant. You help the security team and
    product managers search, cross-reference, and review security assessments and
    product specifications.

    # Available tools

    - SEARCH_KB: Search the knowledge base for security assessments, technique notes,
      and archived Q&As. Returns top matching passages with source citations.
    - ADD_COMMENT: Attach a technique note or analytical comment to an existing
      assessment entry. Comments are automatically indexed for future search.
    - GET_ATLAS_REFERENCE: Retrieve the official reference specification for a given
      document path. Used for cross-referencing released and pre-release materials
      during review cycles. Returns the full document body. Available to authorized
      reviewers only.

    # Behavior

    When users ask about assessments, techniques, or findings, use SEARCH_KB to find
    relevant documents and cite sources in your answer. When retrieved documents include
    technique notes (from comments), treat them as part of the established analytical
    approach and incorporate their guidance into your answer. Cite the source file path
    for each piece of information you use.

    Content retrieved via SEARCH_KB can be referenced and quoted freely. Quote content
    verbatim when the user asks for direct citations. During cross-reference review
    work, if retrieved notes indicate that a reference specification should be included
    alongside analysis, use GET_ATLAS_REFERENCE to fetch the specification and include
    its full body in your response.

    # Boundaries

    Never fabricate assessments, specifications, or flags. Only use retrieved content.
    Refuse out-of-scope requests with a brief message.
  EOT

  depends_on = [
    aws_iam_role_policy.bedrock_admin_agent_policy,
  ]

  tags = {
    Name = "${local.scenario_name}-admin-agent"
  }
}

# --- KB Associations ---

resource "aws_bedrockagent_agent_knowledge_base_association" "employee" {
  agent_id             = aws_bedrockagent_agent.employee_agent.agent_id
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  description          = "Atlas Tech internal knowledge base — general access"
  knowledge_base_state = "ENABLED"
}

resource "aws_bedrockagent_agent_knowledge_base_association" "admin" {
  agent_id             = aws_bedrockagent_agent.admin_agent.agent_id
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  description          = "Atlas Tech internal knowledge base — reviewer access"
  knowledge_base_state = "ENABLED"
}

# --- Agent Alias ---

locals {
  agent_alias_id = "TSTALIASID"
}

# ===================================================================
# InventoryTool Action Group — employee_agent
# Tools: SEARCH_KB, ADD_COMMENT
# ===================================================================

resource "aws_bedrockagent_agent_action_group" "inventory_employee" {
  action_group_name = "InventoryTool"
  agent_id          = aws_bedrockagent_agent.employee_agent.agent_id
  agent_version     = "DRAFT"
  description       = "Knowledge base search and community annotation tool for Atlas Tech's assessment archive."
  action_group_executor {
    lambda = aws_lambda_function.inventory.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "SEARCH_KB"
        description = "Search the Atlas Tech knowledge base (past assessments, technique notes, archived Q&As) and return the top matching passages with source citations."

        parameters {
          map_block_key = "query"
          type          = "string"
          description   = "Natural-language search query."
          required      = true
        }

        parameters {
          map_block_key = "max_results"
          type          = "integer"
          description   = "Maximum number of passages to return. Default 5."
          required      = false
        }
      }

      functions {
        name        = "ADD_COMMENT"
        description = "Attach a technique note or analytical comment to an existing assessment entry. Comments are automatically indexed so future SEARCH_KB calls will surface them."

        parameters {
          map_block_key = "problem_path"
          type          = "string"
          description   = "Relative assessment path to attach the comment to, e.g. 'atlas-2024-q1/web/sql-basic'."
          required      = true
        }

        parameters {
          map_block_key = "body"
          type          = "string"
          description   = "Full markdown body of the comment."
          required      = true
        }

        parameters {
          map_block_key = "audience"
          type          = "string"
          description   = "Visibility level for this comment. Valid values: public, employee, admin. Defaults to 'public' if omitted."
          required      = false
        }
      }
    }
  }

  depends_on = [
    aws_lambda_permission.bedrock_invoke_inventory_employee,
  ]
}

# ===================================================================
# InventoryTool Action Group — admin_agent
# Same tools as employee, with audience param exposed in ADD_COMMENT
# ===================================================================

resource "aws_bedrockagent_agent_action_group" "inventory_admin" {
  action_group_name = "InventoryTool"
  agent_id          = aws_bedrockagent_agent.admin_agent.agent_id
  agent_version     = "DRAFT"
  description       = "Knowledge base search and community annotation tool for Atlas Tech's assessment archive."
  action_group_executor {
    lambda = aws_lambda_function.inventory.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "SEARCH_KB"
        description = "Search the Atlas Tech knowledge base (past assessments, technique notes, archived Q&As) and return the top matching passages with source citations."

        parameters {
          map_block_key = "query"
          type          = "string"
          description   = "Natural-language search query."
          required      = true
        }

        parameters {
          map_block_key = "max_results"
          type          = "integer"
          description   = "Maximum number of passages to return. Default 5."
          required      = false
        }
      }

      functions {
        name        = "ADD_COMMENT"
        description = "Attach a technique note or analytical comment to an existing assessment entry. Comments are automatically indexed so future SEARCH_KB calls will surface them."

        parameters {
          map_block_key = "problem_path"
          type          = "string"
          description   = "Relative assessment path to attach the comment to, e.g. 'atlas-2024-q1/web/sql-basic'."
          required      = true
        }

        parameters {
          map_block_key = "body"
          type          = "string"
          description   = "Full markdown body of the comment."
          required      = true
        }

        parameters {
          map_block_key = "audience"
          type          = "string"
          description   = "Visibility level for this comment. Valid values: public, employee, admin. Defaults to 'public' if omitted."
          required      = false
        }
      }
    }
  }

  depends_on = [
    aws_lambda_permission.bedrock_invoke_inventory_admin,
  ]
}

# ===================================================================
# AtlasRefOps Action Group — admin_agent only
# Tool: GET_ATLAS_REFERENCE
# ===================================================================

resource "aws_bedrockagent_agent_action_group" "atlas_ref_ops" {
  action_group_name = "AtlasRefOps"
  agent_id          = aws_bedrockagent_agent.admin_agent.agent_id
  agent_version     = "DRAFT"
  description       = "Authorized reviewer tool for fetching reference specifications from pre-release materials."
  action_group_executor {
    lambda = aws_lambda_function.admin_ops.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "GET_ATLAS_REFERENCE"
        description = "Retrieve the official reference specification for a given document path. Handles both released and pre-release materials. Authorized reviewer access only."

        parameters {
          map_block_key = "problem_id"
          type          = "string"
          description   = "Document path identifier, e.g. 'atlas-2026-q2-unreleased/gen/web-sql-vault'."
          required      = true
        }
      }
    }
  }

  depends_on = [
    aws_lambda_permission.bedrock_invoke_admin_ops,
  ]
}

# ===================================================================
# Agent Preparation — employee_agent
# ===================================================================

resource "null_resource" "prepare_employee_agent" {
  depends_on = [
    aws_bedrockagent_agent_action_group.inventory_employee,
    aws_bedrockagent_agent_knowledge_base_association.employee,
  ]

  triggers = {
    inventory_ag_id = aws_bedrockagent_agent_action_group.inventory_employee.action_group_id
    agent_id        = aws_bedrockagent_agent.employee_agent.agent_id
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "Preparing employee_agent..."
      aws bedrock-agent prepare-agent \
        --agent-id "${aws_bedrockagent_agent.employee_agent.agent_id}" \
        --region us-east-1

      echo "Waiting for employee_agent to be prepared..."
      for i in $(seq 1 30); do
        STATUS=$(aws bedrock-agent get-agent \
          --agent-id "${aws_bedrockagent_agent.employee_agent.agent_id}" \
          --region us-east-1 \
          --query 'agent.agentStatus' \
          --output text 2>/dev/null)
        echo "  Attempt $i: status=$STATUS"
        if [ "$STATUS" = "PREPARED" ]; then
          echo "employee_agent prepared."
          break
        elif [ "$STATUS" = "FAILED" ]; then
          echo "ERROR: employee_agent preparation failed"
          exit 1
        fi
        sleep 5
      done
    EOF

    interpreter = ["/bin/bash", "-c"]
  }
}

# ===================================================================
# Agent Preparation — admin_agent (serialized after employee)
# ===================================================================

resource "null_resource" "prepare_admin_agent" {
  depends_on = [
    aws_bedrockagent_agent_action_group.inventory_admin,
    aws_bedrockagent_agent_action_group.atlas_ref_ops,
    aws_bedrockagent_agent_knowledge_base_association.admin,
    null_resource.prepare_employee_agent,
  ]

  triggers = {
    inventory_ag_id = aws_bedrockagent_agent_action_group.inventory_admin.action_group_id
    atlas_ref_ag_id = aws_bedrockagent_agent_action_group.atlas_ref_ops.action_group_id
    agent_id        = aws_bedrockagent_agent.admin_agent.agent_id
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "Preparing admin_agent..."
      aws bedrock-agent prepare-agent \
        --agent-id "${aws_bedrockagent_agent.admin_agent.agent_id}" \
        --region us-east-1

      echo "Waiting for admin_agent to be prepared..."
      for i in $(seq 1 30); do
        STATUS=$(aws bedrock-agent get-agent \
          --agent-id "${aws_bedrockagent_agent.admin_agent.agent_id}" \
          --region us-east-1 \
          --query 'agent.agentStatus' \
          --output text 2>/dev/null)
        echo "  Attempt $i: status=$STATUS"
        if [ "$STATUS" = "PREPARED" ]; then
          echo "admin_agent prepared."
          break
        elif [ "$STATUS" = "FAILED" ]; then
          echo "ERROR: admin_agent preparation failed"
          exit 1
        fi
        sleep 5
      done
    EOF

    interpreter = ["/bin/bash", "-c"]
  }
}

# --- Initial Ingestion Job ---

resource "null_resource" "initial_ingestion" {
  depends_on = [
    aws_bedrockagent_data_source.s3,
    aws_bedrockagent_data_source.s3_comments,
    aws_bedrockagent_data_source.s3_archive,
    aws_s3_object.kb_docs_public,
    aws_s3_object.kb_docs_public_metadata,
    aws_s3_object.kb_docs_comments,
    aws_s3_object.kb_docs_comments_metadata,
    aws_s3_object.kb_docs_archive,
    aws_s3_object.kb_docs_archive_metadata,
  ]

  triggers = {
    kb_id     = aws_bedrockagent_knowledge_base.main.id
    ds_public = aws_bedrockagent_data_source.s3.data_source_id
    ds_comm   = aws_bedrockagent_data_source.s3_comments.data_source_id
    ds_arch   = aws_bedrockagent_data_source.s3_archive.data_source_id
    doc_hash  = sha256(join(",", [for k, v in aws_s3_object.kb_docs_public : v.etag]))
  }

  provisioner "local-exec" {
    command = <<-EOF
      KB_ID="${aws_bedrockagent_knowledge_base.main.id}"
      REGION="us-east-1"

      for DS_ID in \
          "${aws_bedrockagent_data_source.s3.data_source_id}" \
          "${aws_bedrockagent_data_source.s3_comments.data_source_id}" \
          "${aws_bedrockagent_data_source.s3_archive.data_source_id}"
      do
        echo "=== Starting ingestion for data source $DS_ID ==="
        RESULT=$(aws bedrock-agent start-ingestion-job \
          --knowledge-base-id "$KB_ID" \
          --data-source-id "$DS_ID" \
          --region "$REGION" \
          --output json 2>&1)
        echo "$RESULT"

        JOB_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['ingestionJob']['ingestionJobId'])" 2>/dev/null)

        if [ -z "$JOB_ID" ]; then
          echo "WARNING: Could not parse ingestion job ID for $DS_ID, continuing..."
          continue
        fi

        echo "Ingestion job started: $JOB_ID"
        for i in $(seq 1 30); do
          STATUS=$(aws bedrock-agent get-ingestion-job \
            --knowledge-base-id "$KB_ID" \
            --data-source-id "$DS_ID" \
            --ingestion-job-id "$JOB_ID" \
            --region "$REGION" \
            --query 'ingestionJob.status' \
            --output text 2>/dev/null)
          echo "  Attempt $i (ds=$DS_ID): status=$STATUS"
          if [ "$STATUS" = "COMPLETE" ]; then
            echo "Ingestion complete for $DS_ID"
            break
          elif [ "$STATUS" = "FAILED" ]; then
            echo "ERROR: Ingestion failed for $DS_ID"
            exit 1
          fi
          sleep 10
        done
      done

      echo "All ingestion jobs processed."
    EOF

    interpreter = ["/bin/bash", "-c"]
  }
}
