# OpenSearch Serverless — Vector store for Bedrock Knowledge Base
# Stage 1: Collection + policies + vector index (via null_resource)

locals {
  # Short prefix for OpenSearch Serverless (policy names max 32 chars, collection names max 32 chars)
  oss_prefix     = "bkp-${local.cg_id}"
  oss_collection = "bkp-kb-${local.cg_id}"
}

resource "aws_opensearchserverless_security_policy" "kb_encryption" {
  name = "${local.oss_prefix}-enc"
  type = "encryption"

  policy = jsonencode({
    Rules = [
      {
        Resource     = ["collection/${local.oss_collection}"]
        ResourceType = "collection"
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "kb_network" {
  name = "${local.oss_prefix}-net"
  type = "network"

  policy = jsonencode([
    {
      Rules = [
        {
          Resource     = ["collection/${local.oss_collection}"]
          ResourceType = "collection"
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "kb_data_access" {
  name = "${local.oss_prefix}-dap"
  type = "data"

  policy = jsonencode([
    {
      Rules = [
        {
          Resource     = ["collection/${local.oss_collection}"]
          ResourceType = "collection"
          Permission = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems",
          ]
        },
        {
          Resource     = ["index/${local.oss_collection}/*"]
          ResourceType = "index"
          Permission = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
          ]
        }
      ]
      # Decoy (B): Only Bedrock KB role has AOSS data access.
      # The solver discovers the OpenSearch endpoint but cannot access it
      # directly — neither cloudgoat user nor Lambda proxy role are permitted.
      Principal = [
        aws_iam_role.bedrock_kb_role.arn,
        data.aws_caller_identity.current.arn,
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name = local.oss_collection
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.kb_encryption,
    aws_opensearchserverless_security_policy.kb_network,
    aws_opensearchserverless_access_policy.kb_data_access,
  ]

  tags = {
    Name = "${local.scenario_name}-kb-collection"
  }
}

# Create vector index using opensearch-py (KB does NOT auto-create it)
resource "null_resource" "create_vector_index" {
  depends_on = [aws_opensearchserverless_collection.kb]

  triggers = {
    collection_endpoint = aws_opensearchserverless_collection.kb.collection_endpoint
  }

  provisioner "local-exec" {
    command = <<-EOF
      python3 - <<'PYEOF'
import json
import time
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth

# Wait for collection to be ACTIVE
aoss = boto3.client('opensearchserverless', region_name='us-east-1')
collection_name = "${aws_opensearchserverless_collection.kb.name}"

print(f"Waiting for collection {collection_name} to become ACTIVE...")
for attempt in range(30):
    resp = aoss.batch_get_collection(names=[collection_name])
    details = resp.get('collectionDetails', [])
    if details and details[0].get('status') == 'ACTIVE':
        print(f"Collection is ACTIVE after {attempt * 10}s")
        break
    print(f"  Status: {details[0].get('status') if details else 'unknown'}, waiting...")
    time.sleep(10)
else:
    raise Exception("Collection did not become ACTIVE within 300s")

endpoint = "${aws_opensearchserverless_collection.kb.collection_endpoint}"
host = endpoint.replace("https://", "")

credentials = boto3.Session().get_credentials()
auth = AWSV4SignerAuth(credentials, 'us-east-1', 'aoss')

client = OpenSearch(
    hosts=[{'host': host, 'port': 443}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    timeout=60,
)

index_name = "bedrock-knowledge-base-default-index"

# Check if index already exists
try:
    if client.indices.exists(index=index_name):
        print(f"Index {index_name} already exists, skipping creation")
        exit(0)
except Exception as e:
    print(f"Index check error (may not exist yet): {e}")

index_body = {
    "settings": {
        "index.knn": True,
        "number_of_shards": 2,
        "number_of_replicas": 0,
    },
    "mappings": {
        "properties": {
            "bedrock-knowledge-base-default-vector": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                    "engine": "faiss",
                    "name": "hnsw",
                    "parameters": {
                        "m": 16,
                        "ef_construction": 512,
                    }
                }
            },
            "AMAZON_BEDROCK_METADATA": {
                "type": "text",
                "index": False,
            },
            "AMAZON_BEDROCK_TEXT_CHUNK": {
                "type": "text",
            },
        }
    }
}

print(f"Creating vector index: {index_name}")
response = client.indices.create(index=index_name, body=index_body)
print(f"Index created: {json.dumps(response)}")
PYEOF
    EOF

    interpreter = ["/bin/bash", "-c"]
  }
}
