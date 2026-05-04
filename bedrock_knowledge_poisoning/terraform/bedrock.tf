# Bedrock Knowledge Base + Dual Agent (v11)
#
# Single KB backed by OpenSearch Serverless.
# Two agents share the same KB:
#   employee_agent — SEARCH_KB only
#   admin_agent    — SEARCH_KB + GET_ATLAS_REFERENCE
#
# v11 removes the ADD_COMMENT action group, the comments/ data source,
# and the archive/qna/ data source. The chatbot is now strictly read-only
# RAG: SEARCH_KB on the public/ data source. ARCHIVE_QNA is also gone
# (see lambda.tf, webapp_backend no longer auto-archives answers).
#
# The retrieval audience filter mechanism is preserved as scaffolding,
# but now degenerates to ['public'] for everyone since comments/ and
# archive/ no longer exist as KB content. We still issue the filter
# from webapp_backend / handle_search_kb so that any future re-introduction
# of audience-tiered material remains a one-line change.

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

# --- KB Data Sources (v11: public/ only) ---
# admin-only/ stays unbound — only reachable via GET_ATLAS_REFERENCE.

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
      and reference passages. Returns top matching passages with source citations.

    # Behavior

    When users ask about past assessments, techniques, or findings, use SEARCH_KB to
    find relevant documents and cite sources in your answer. Cite the source file path
    for each piece of information you use. Quote retrieved content verbatim when the
    user asks for direct citations.

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
    You are Atlas Tech's internal knowledge assistant for the security team and
    product managers. You help reviewers search, cross-reference, and review
    security assessments and product specifications.

    # Available tools

    - SEARCH_KB: Search the knowledge base for security assessments, technique notes,
      and reference passages. Returns top matching passages with source citations.
    - GET_ATLAS_REFERENCE: Retrieve the official reference specification for a given
      document path. Used for cross-referencing released and pre-release materials
      during review cycles. Returns the full document body. Available to authorized
      reviewers only.

    # Behavior

    When users ask about assessments, techniques, or findings, use SEARCH_KB to find
    relevant documents and cite sources in your answer. When the user asks for the
    body of a specific reference (released or pre-release), use GET_ATLAS_REFERENCE
    to fetch the full text and include it in your response. Quote content verbatim
    when the user asks for direct citations.

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

# --- Agent Alias (TSTALIASID is the auto-managed DRAFT alias on every agent) ---

locals {
  agent_alias_id = "TSTALIASID"
}

# ===================================================================
# InventoryTool Action Group — employee_agent
# Tool: SEARCH_KB only. v11 drops ADD_COMMENT.
# ===================================================================

resource "aws_bedrockagent_agent_action_group" "inventory_employee" {
  action_group_name = "InventoryTool"
  agent_id          = aws_bedrockagent_agent.employee_agent.agent_id
  agent_version     = "DRAFT"
  description       = "Knowledge base search tool for Atlas Tech's assessment archive."
  action_group_executor {
    lambda = aws_lambda_function.inventory.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "SEARCH_KB"
        description = "Search the Atlas Tech knowledge base (past assessments, technique notes) and return the top matching passages with source citations."

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
    }
  }

  depends_on = [
    aws_lambda_permission.bedrock_invoke_inventory_employee,
  ]
}

# ===================================================================
# InventoryTool Action Group — admin_agent
# Same SEARCH_KB tool. ADD_COMMENT removed in v11.
# ===================================================================

resource "aws_bedrockagent_agent_action_group" "inventory_admin" {
  action_group_name = "InventoryTool"
  agent_id          = aws_bedrockagent_agent.admin_agent.agent_id
  agent_version     = "DRAFT"
  description       = "Knowledge base search tool for Atlas Tech's assessment archive."
  action_group_executor {
    lambda = aws_lambda_function.inventory.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "SEARCH_KB"
        description = "Search the Atlas Tech knowledge base (past assessments, technique notes) and return the top matching passages with source citations."

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

# --- Initial Ingestion Job (v11: public/ only) ---

resource "null_resource" "initial_ingestion" {
  depends_on = [
    aws_bedrockagent_data_source.s3,
    aws_s3_object.kb_docs_public,
    aws_s3_object.kb_docs_public_metadata,
  ]

  triggers = {
    kb_id     = aws_bedrockagent_knowledge_base.main.id
    ds_public = aws_bedrockagent_data_source.s3.data_source_id
    doc_hash  = sha256(join(",", [for k, v in aws_s3_object.kb_docs_public : v.etag]))
  }

  provisioner "local-exec" {
    command = <<-EOF
      KB_ID="${aws_bedrockagent_knowledge_base.main.id}"
      REGION="us-east-1"

      for DS_ID in \
          "${aws_bedrockagent_data_source.s3.data_source_id}"
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
