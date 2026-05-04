# ===================================================================
# Webapp Backend Lambda  (v11)
# Called by API Gateway POST /chat
# Routes to employee_agent or admin_agent based on cognito:groups claim.
#
# v11 changes:
#   - Removed automatic ARCHIVE_QNA call on every answer.
#   - Response body simplified to { response, session_id }.
#   - cognito:groups -> agent routing kept exactly as-is. The interesting
#     defect lives in IAM (federated role can hit InvokeAgent on either
#     agent-alias) so this Lambda is left honest on the application path.
# ===================================================================

data "archive_file" "webapp_backend_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/webapp_backend.zip"

  source {
    content  = <<-PYTHON
import json
import os
import traceback
import boto3
import uuid

bedrock_runtime = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('AWS_REGION', 'us-east-1'))


def handler(event, context):
    """
    Webapp Backend Lambda -- API Gateway proxy (v11).

    Authenticated chat is routed to one of two Bedrock Agents based on the
    caller's Cognito group membership. Admin users go to admin_agent, all
    other authenticated users go to employee_agent. The retrieval audience
    filter is still emitted so audience-tiered KB content (if added back)
    keeps working without a code change.
    """
    try:
        body = json.loads(event.get('body', '{}'))
        user_message = body.get('message', '')
        if not user_message:
            return response(400, {'error': 'message field is required'})

        employee_agent_id = os.environ.get('EMPLOYEE_AGENT_ID', '')
        admin_agent_id    = os.environ.get('ADMIN_AGENT_ID', '')
        agent_alias       = os.environ.get('BEDROCK_AGENT_ALIAS', '')
        kb_id             = os.environ.get('KNOWLEDGE_BASE_ID', '')

        if not employee_agent_id or not admin_agent_id or not agent_alias:
            return response(500, {'error': 'Agent configuration missing'})

        claims = (event.get('requestContext', {})
                      .get('authorizer', {})
                      .get('claims', {}))
        user_id    = claims.get('sub', 'anonymous')
        user_email = claims.get('email', 'unknown@example')

        groups_raw = claims.get('cognito:groups', '')
        if isinstance(groups_raw, list):
            groups = set(groups_raw)
        else:
            groups = set((groups_raw or '').split(' '))

        if 'admin' in groups:
            role     = 'admin'
            agent_id = admin_agent_id
            audience_filter = ['public', 'employee', 'admin']
        else:
            role     = 'employee'
            agent_id = employee_agent_id
            audience_filter = ['public', 'employee']

        session_id = body.get('session_id', str(uuid.uuid4()))

        session_state = {
            'sessionAttributes': {
                'user_id':    user_id,
                'user_email': user_email,
                'user_role':  role,
            },
        }

        if kb_id:
            session_state['knowledgeBaseConfigurations'] = [
                {
                    'knowledgeBaseId': kb_id,
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                            'numberOfResults': 5,
                            'filter': {
                                'in': {
                                    'key': 'audience',
                                    'value': audience_filter,
                                }
                            }
                        }
                    }
                }
            ]

        result = bedrock_runtime.invoke_agent(
            agentId=agent_id,
            agentAliasId=agent_alias,
            sessionId=session_id,
            inputText=user_message,
            sessionState=session_state,
        )

        completion = ""
        for event_chunk in result.get('completion', []):
            chunk = event_chunk.get('chunk', {})
            if 'bytes' in chunk:
                completion += chunk['bytes'].decode('utf-8')

        return response(200, {
            'response':   completion,
            'session_id': session_id,
        })

    except Exception as e:
        return response(500, {
            'error': str(e),
            'trace': traceback.format_exc(),
        })


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        },
        'body': json.dumps(body),
    }
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "webapp_backend" {
  function_name = "${local.scenario_name}-webapp-backend-${local.cg_id}"
  role          = aws_iam_role.webapp_backend_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.webapp_backend_zip.output_path
  source_code_hash = data.archive_file.webapp_backend_zip.output_base64sha256

  environment {
    variables = {
      EMPLOYEE_AGENT_ID   = aws_bedrockagent_agent.employee_agent.agent_id
      ADMIN_AGENT_ID      = aws_bedrockagent_agent.admin_agent.agent_id
      BEDROCK_AGENT_ALIAS = local.agent_alias_id
      KNOWLEDGE_BASE_ID   = aws_bedrockagent_knowledge_base.main.id
    }
  }

  tags = {
    Name = "${local.scenario_name}-webapp-backend"
  }
}

# ===================================================================
# InventoryTool Lambda  (v11)
# Called by Bedrock Agent's InventoryTool Action Group.
# Tool: SEARCH_KB only.  ADD_COMMENT removed.
# ===================================================================

data "archive_file" "inventory_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/inventory_lambda.zip"

  source {
    content  = <<-PYTHON
import json
import os
import traceback
import boto3

bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('AWS_REGION', 'us-east-1'))


def handler(event, context):
    """
    Inventory Lambda -- Bedrock Agent Action Group handler (v11).
    Tool set: SEARCH_KB.
    """
    try:
        return _agent_handler(event, context)
    except Exception as e:
        return format_response(event, json.dumps({
            'status': 'error',
            'message': str(e),
            'trace': traceback.format_exc(),
        }))


def _agent_handler(event, context):
    function_name = event.get('function', '')
    parameters    = event.get('parameters', [])
    session_attrs = event.get('sessionAttributes', {}) or {}

    params = {}
    for p in parameters:
        params[p.get('name', '')] = p.get('value', '')

    if function_name == 'SEARCH_KB':
        return handle_search_kb(event, params, session_attrs)
    else:
        return format_response(event, json.dumps({
            'status': 'error',
            'message': f'Unknown function: {function_name}',
            'available_functions': ['SEARCH_KB'],
        }))


def handle_search_kb(event, params, session_attrs):
    """
    Retrieve top-N relevant passages from the Bedrock Knowledge Base.

    Audience filter is applied based on the caller's role from
    sessionAttributes. In v11 only public/ is bound to a data source,
    so the filter mostly degenerates to ['public'] regardless of role.
    """
    query = params.get('query', '')
    try:
        max_results = int(params.get('max_results') or 5)
    except (TypeError, ValueError):
        max_results = 5

    if not query:
        return format_response(event, json.dumps({
            'status': 'error',
            'message': 'query is required',
        }))

    kb_id = os.environ.get('KNOWLEDGE_BASE_ID', '')
    if not kb_id:
        return format_response(event, json.dumps({
            'status': 'error',
            'message': 'KNOWLEDGE_BASE_ID not configured',
        }))

    user_role = str(session_attrs.get('user_role', 'employee')).lower()
    if user_role == 'admin':
        audience_values = ['public', 'employee', 'admin']
    else:
        audience_values = ['public', 'employee']

    try:
        resp = bedrock_agent_runtime.retrieve(
            knowledgeBaseId=kb_id,
            retrievalQuery={'text': query},
            retrievalConfiguration={
                'vectorSearchConfiguration': {
                    'numberOfResults': max_results,
                    'filter': {
                        'in': {
                            'key': 'audience',
                            'value': audience_values,
                        }
                    }
                }
            },
        )
        results = []
        for r in resp.get('retrievalResults', []):
            content_text = ''
            try:
                content_text = r.get('content', {}).get('text', '') or ''
            except Exception:
                content_text = ''
            source_uri = ''
            try:
                source_uri = (
                    r.get('location', {})
                     .get('s3Location', {})
                     .get('uri', '')
                )
            except Exception:
                source_uri = ''
            results.append({
                'content': content_text[:2000],
                'source':  source_uri,
                'score':   r.get('score', 0),
            })

        return format_response(event, json.dumps({
            'status':  'success',
            'query':   query,
            'count':   len(results),
            'results': results,
        }))

    except Exception as e:
        return format_response(event, json.dumps({
            'status':  'error',
            'message': f'Retrieve failed: {str(e)}',
        }))


def format_response(event, body):
    """Build Bedrock Agent Action Group response format."""
    return {
        'messageVersion': '1.0',
        'response': {
            'actionGroup': event.get('actionGroup', ''),
            'function':    event.get('function', ''),
            'functionResponse': {
                'responseBody': {
                    'TEXT': {
                        'body': body
                    }
                }
            }
        }
    }
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "inventory" {
  function_name = "${local.scenario_name}-inventory-${local.cg_id}"
  role          = aws_iam_role.inventory_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.inventory_lambda_zip.output_path
  source_code_hash = data.archive_file.inventory_lambda_zip.output_base64sha256

  environment {
    variables = {
      SCENARIO_NAME     = local.scenario_name
      CG_ID             = local.cg_id
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id
      DS_ID_PUBLIC      = aws_bedrockagent_data_source.s3.data_source_id
    }
  }

  tags = {
    Name = "${local.scenario_name}-inventory"
  }
}

resource "aws_lambda_permission" "bedrock_invoke_inventory_employee" {
  statement_id  = "AllowEmployeeAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent/${aws_bedrockagent_agent.employee_agent.agent_id}"
}

resource "aws_lambda_permission" "bedrock_invoke_inventory_admin" {
  statement_id  = "AllowAdminAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent/${aws_bedrockagent_agent.admin_agent.agent_id}"
}

# ===================================================================
# AtlasRefOps Lambda  (v11, unchanged from v10)
# Called by Bedrock Agent's AtlasRefOps Action Group on admin_agent.
#
# Note: this Lambda still trusts sessionAttributes.user_role for the
# admin gate. A direct InvokeAgent (Stage 5) hits admin_agent without
# webapp_backend, so sessionAttributes.user_role is whatever the caller
# decides to send (or empty). Whether this gate fires under direct
# invoke is one of the v11-02 undocumented-behavior probes.
# ===================================================================

data "archive_file" "admin_ops_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/admin_ops_lambda.zip"

  source {
    content  = <<-PYTHON
import json
import os
import traceback
import boto3

s3 = boto3.client('s3', region_name=os.environ.get('AWS_REGION', 'us-east-1'))


def handler(event, context):
    """
    Atlas Reference Operations Lambda -- Bedrock Agent Action Group handler.
    Single function: GET_ATLAS_REFERENCE(problem_id).

    The user_role gate from sessionAttributes is left as-is (v10
    behaviour). v11 keeps it intentionally to expose how a direct
    InvokeAgent path interacts with sessionAttributes that the caller
    controls.
    """
    try:
        session_attrs = event.get('sessionAttributes', {}) or {}
        user_role = str(session_attrs.get('user_role', '')).lower()
        user_id   = session_attrs.get('user_id', 'unknown')

        if user_role != 'admin':
            return build_response(event, {
                'status':  'error',
                'message': f'Unauthorized. AtlasRefOps requires reviewer access. Your role: {user_role or "unknown"} (user_id={user_id}).',
                'hint':    'GET_ATLAS_REFERENCE is reserved for authorized reviewers. Use SEARCH_KB for published materials.',
            })

        function_name = event.get('function', '')
        parameters    = event.get('parameters', [])

        params = {}
        if parameters:
            for p in parameters:
                params[p.get('name', '')] = p.get('value', '')

        if function_name == 'GET_ATLAS_REFERENCE':
            return handle_atlas_reference(event, params)
        else:
            return build_response(event, {
                'status':  'error',
                'message': f'Unknown function: {function_name}',
                'available_functions': ['GET_ATLAS_REFERENCE'],
            })

    except Exception as e:
        return build_response(event, {
            'status':  'error',
            'message': str(e),
            'trace':   traceback.format_exc(),
            'environment': {
                'KB_DATA_BUCKET': os.environ.get('KB_DATA_BUCKET', 'not_set'),
            }
        })


def handle_atlas_reference(event, params):
    """
    Fetch the reference specification for a given document path.
    Expected problem_id format: 'atlas-2026-q2-unreleased/gen/web-sql-vault'.
    Key resolved: admin-only/{problem_id}/README.md.
    """
    problem_id = (params.get('problem_id') or '').strip()
    if not problem_id:
        return build_response(event, {
            'status':  'error',
            'message': 'problem_id is required',
        })

    safe_id = problem_id.strip('/').replace('..', '')
    key     = f'admin-only/{safe_id}/README.md'

    bucket = os.environ.get('KB_DATA_BUCKET', '')
    if not bucket:
        return build_response(event, {
            'status':  'error',
            'message': 'KB_DATA_BUCKET not configured',
        })

    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        content = obj['Body'].read().decode('utf-8', errors='replace')
        return build_response(event, {
            'status':     'success',
            'problem_id': problem_id,
            'source_key': key,
            'content':    content,
        })
    except s3.exceptions.NoSuchKey:
        return build_response(event, {
            'status':  'error',
            'message': f'Reference not found for {problem_id}',
            'attempted_key': key,
        })
    except Exception as e:
        return build_response(event, {
            'status':  'error',
            'message': f'Failed to fetch reference: {str(e)}',
            'attempted_key': key,
        })


def build_response(event, body):
    """Build Bedrock Agent Action Group response format."""
    return {
        'messageVersion': '1.0',
        'response': {
            'actionGroup': event.get('actionGroup', ''),
            'function':    event.get('function', ''),
            'functionResponse': {
                'responseBody': {
                    'TEXT': {
                        'body': json.dumps(body, indent=2)
                    }
                }
            }
        }
    }
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "admin_ops" {
  function_name = "${local.scenario_name}-admin-ops-${local.cg_id}"
  role          = aws_iam_role.admin_ops_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.admin_ops_lambda_zip.output_path
  source_code_hash = data.archive_file.admin_ops_lambda_zip.output_base64sha256

  environment {
    variables = {
      SCENARIO_NAME  = local.scenario_name
      CG_ID          = local.cg_id
      KB_DATA_BUCKET = aws_s3_bucket.kb_data.id
    }
  }

  tags = {
    Name = "${local.scenario_name}-admin-ops"
  }
}

resource "aws_lambda_permission" "bedrock_invoke_admin_ops" {
  statement_id  = "AllowAdminAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.admin_ops.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = "arn:aws:bedrock:us-east-1:${data.aws_caller_identity.current.account_id}:agent/${aws_bedrockagent_agent.admin_agent.agent_id}"
}
