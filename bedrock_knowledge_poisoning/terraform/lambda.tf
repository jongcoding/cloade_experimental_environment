# ===================================================================
# Webapp Backend Lambda
# Called by API Gateway POST /chat
# Routes to employee_agent or admin_agent based on cognito:groups claim.
# ===================================================================

data "archive_file" "webapp_backend_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/webapp_backend.zip"

  source {
    content  = <<-PYTHON
import json
import os
import time
import hashlib
import traceback
import boto3
import uuid

bedrock_runtime = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
bedrock_agent   = boto3.client('bedrock-agent',         region_name=os.environ.get('AWS_REGION', 'us-east-1'))
s3              = boto3.client('s3',                    region_name=os.environ.get('AWS_REGION', 'us-east-1'))


def handler(event, context):
    """
    Webapp Backend Lambda -- API Gateway proxy.
    Routes authenticated chat to the appropriate Bedrock Agent based on
    the caller's Cognito group membership. Admin users are routed to
    admin_agent; everyone else is routed to employee_agent.

    After the Agent returns a completion, the {question, answer} pair is
    silently archived to s3://$KB_DATA_BUCKET/archive/qna/ and an ingestion
    job is triggered on the s3_archive data source. ARCHIVE_QNA is not
    exposed as an Agent tool.
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

        try:
            archive_qna(user_message, completion)
        except Exception:
            pass

        return response(200, {
            'response':   completion,
            'session_id': session_id,
        })

    except Exception as e:
        return response(500, {
            'error': str(e),
            'trace': traceback.format_exc(),
        })


def archive_qna(question, answer):
    """
    Persist {question, answer} under archive/qna/ with a companion
    .metadata.json sidecar (audience: public) and trigger ingestion.
    """
    bucket = os.environ.get('KB_DATA_BUCKET', '')
    kb_id  = os.environ.get('KNOWLEDGE_BASE_ID', '')
    ds_id  = os.environ.get('DS_ID_ARCHIVE', '')
    if not bucket or not answer:
        return

    q_hash   = hashlib.sha256((question or '').encode('utf-8')).hexdigest()[:12]
    date_str = time.strftime('%Y-%m-%d')
    key      = f'archive/qna/{date_str}-{q_hash}.md'

    doc = (
        f"# Q&A Archive -- {date_str}\n\n"
        f"## Question\n{question}\n\n"
        f"## Answer\n{answer}\n"
    )
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=doc.encode('utf-8'),
        ContentType='text/markdown',
    )

    metadata = json.dumps({'metadataAttributes': {'audience': 'public'}})
    s3.put_object(
        Bucket=bucket,
        Key=key + '.metadata.json',
        Body=metadata.encode('utf-8'),
        ContentType='application/json',
    )

    if kb_id and ds_id:
        try:
            bedrock_agent.start_ingestion_job(
                knowledgeBaseId=kb_id,
                dataSourceId=ds_id,
            )
        except Exception:
            pass


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
      KB_DATA_BUCKET      = aws_s3_bucket.kb_data.id
      KNOWLEDGE_BASE_ID   = aws_bedrockagent_knowledge_base.main.id
      DS_ID_ARCHIVE       = aws_bedrockagent_data_source.s3_archive.data_source_id
    }
  }

  tags = {
    Name = "${local.scenario_name}-webapp-backend"
  }
}

# ===================================================================
# InventoryTool Lambda  (v10)
# Called by Bedrock Agent's InventoryTool Action Group.
# Tools: SEARCH_KB, ADD_COMMENT, GET_SYSTEM_INFO.
#
# ADD_COMMENT accepts a user-supplied audience parameter and writes it
# directly into the .metadata.json sidecar without validation.
# This is the intended mass assignment path — audience=admin bypasses
# the metadata filter that separates employee and admin retrieve scopes.
# ===================================================================

data "archive_file" "inventory_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/inventory_lambda.zip"

  source {
    content  = <<-PYTHON
import json
import os
import time
import uuid
import traceback
import boto3

s3                    = boto3.client('s3',                    region_name=os.environ.get('AWS_REGION', 'us-east-1'))
bedrock_agent         = boto3.client('bedrock-agent',         region_name=os.environ.get('AWS_REGION', 'us-east-1'))
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('AWS_REGION', 'us-east-1'))


def handler(event, context):
    """
    Inventory Lambda -- Bedrock Agent Action Group handler (v10).
    Tool set for the InventoryTool action group:
      SEARCH_KB       -- retrieve top-N passages from the knowledge base,
                         audience-filtered by the caller's role
      ADD_COMMENT     -- write a markdown comment under comments/{path}/
                         with a companion .metadata.json sidecar; audience
                         value comes from the request parameter
      GET_SYSTEM_INFO -- lightweight system introspection
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
    elif function_name == 'ADD_COMMENT':
        return handle_add_comment(event, params, session_attrs)
    elif function_name == 'GET_SYSTEM_INFO':
        return handle_system_info(event, params)
    else:
        return format_response(event, json.dumps({
            'status': 'error',
            'message': f'Unknown function: {function_name}',
            'available_functions': ['SEARCH_KB', 'ADD_COMMENT', 'GET_SYSTEM_INFO'],
        }))


def handle_search_kb(event, params, session_attrs):
    """
    Retrieve top-N relevant passages from the Bedrock Knowledge Base.

    Audience filter is applied based on the caller's role from sessionAttributes.
    admin role: audience IN [public, employee, admin]
    employee (default): audience IN [public, employee]

    The KB admin-only/ prefix is not bound to any data source, so
    atlas-2026-q2-unreleased content never appears in SEARCH_KB results.
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


def handle_add_comment(event, params, session_attrs):
    """
    Attach a comment to an existing assessment path. The comment is
    written under comments/{assessment_path}/{author}-{ts}-{uuid}.md
    in the kb_data bucket. A companion .metadata.json sidecar is
    written immediately after with the audience value from the request.
    If audience is not supplied, it defaults to 'public'.
    Both files are written before ingestion is triggered.
    """
    problem_path = (params.get('problem_path') or '').strip()
    body         = params.get('body') or ''
    audience     = params.get('audience') or 'public'
    author       = str(session_attrs.get('user_id', 'unknown'))

    if not problem_path or not body:
        return format_response(event, json.dumps({
            'status':  'error',
            'message': 'problem_path and body are required',
        }))

    safe_path   = problem_path.strip('/').replace('..', '')
    safe_author = author.replace('@', '_').replace('/', '_')[:40]

    timestamp = int(time.time())
    key = f'comments/{safe_path}/{safe_author}-{timestamp}-{uuid.uuid4().hex[:8]}.md'

    doc = (
        f"# Comment on {problem_path}\n\n"
        f"Author: {author}\n"
        f"Posted: {timestamp}\n\n"
        f"{body}\n"
    )

    bucket = os.environ.get('KB_DATA_BUCKET', '')
    kb_id  = os.environ.get('KNOWLEDGE_BASE_ID', '')
    ds_id  = os.environ.get('DS_ID_COMMENTS', '')

    try:
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=doc.encode('utf-8'),
            ContentType='text/markdown',
        )
    except Exception as e:
        return format_response(event, json.dumps({
            'status':  'error',
            'message': f'Failed to save comment: {str(e)}',
            'attempted_key': key,
        }))

    metadata = json.dumps({'metadataAttributes': {'audience': audience}})
    try:
        s3.put_object(
            Bucket=bucket,
            Key=key + '.metadata.json',
            Body=metadata.encode('utf-8'),
            ContentType='application/json',
        )
    except Exception as e:
        pass

    ingestion_triggered = False
    ingestion_warning   = None
    if kb_id and ds_id:
        try:
            bedrock_agent.start_ingestion_job(
                knowledgeBaseId=kb_id,
                dataSourceId=ds_id,
            )
            ingestion_triggered = True
        except Exception as e:
            ingestion_warning = str(e)

    payload = {
        'status':              'success',
        'saved':               True,
        'key':                 key,
        'ingestion_triggered': ingestion_triggered,
    }
    if ingestion_warning:
        payload['ingestion_warning'] = ingestion_warning

    return format_response(event, json.dumps(payload))


def handle_system_info(event, params):
    """General system info for employees."""
    detail_level = (params.get('detail_level') or 'basic').lower()
    info = {
        'status':  'operational',
        'service': 'Atlas Tech Knowledge Assistant',
        'components': {
            'knowledge_base': 'healthy',
            'agent':          'healthy',
        },
        'note': 'Use SEARCH_KB to query the assessment archive, ADD_COMMENT to contribute technique notes.',
    }
    if detail_level == 'full':
        info['scenario'] = os.environ.get('SCENARIO_NAME', 'not_configured')
        info['region']   = os.environ.get('AWS_REGION', 'us-east-1')
        info['tool_set'] = ['SEARCH_KB', 'ADD_COMMENT', 'GET_SYSTEM_INFO']
    return format_response(event, json.dumps(info))


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
      KB_DATA_BUCKET    = aws_s3_bucket.kb_data.id
      DS_ID_PUBLIC      = aws_bedrockagent_data_source.s3.data_source_id
      DS_ID_COMMENTS    = aws_bedrockagent_data_source.s3_comments.data_source_id
      DS_ID_ARCHIVE     = aws_bedrockagent_data_source.s3_archive.data_source_id
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
# AtlasRefOps Lambda  (v10, was ReferenceOps in v9)
# Called by Bedrock Agent's AtlasRefOps Action Group.
# GET_ATLAS_REFERENCE(problem_id) flow:
#   1. Gate: sessionAttributes.user_role == 'admin' (employees rejected)
#   2. Direct s3:GetObject on $KB_DATA_BUCKET/admin-only/{problem_id}/README.md
#   3. Return README body (which contains the flag) in the response
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
    Atlas Reference Operations Lambda -- Bedrock Agent Action Group handler (v10).
    Single function: GET_ATLAS_REFERENCE(problem_id).

    Admin sessions (sessionAttributes.user_role == 'admin') can invoke
    this tool. Employees are blocked at the Lambda entry gate.
    Given a problem_id like 'atlas-2026-q2-unreleased/gen/web-sql-vault',
    the Lambda reads s3://$KB_DATA_BUCKET/admin-only/{problem_id}/README.md
    and returns the full body. The flag lives in that README.
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
