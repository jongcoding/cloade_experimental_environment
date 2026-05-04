# ===================================================================
# S3 Bucket for Bedrock Knowledge Base data source (v11)
#
# Single bucket, two prefixes:
#   public/      Atlas Tech past assessments + ops SOPs (KB-indexed)
#   admin-only/  atlas-2026-q2-unreleased drafts (NOT KB-indexed;
#                admin-only via GET_ATLAS_REFERENCE direct S3 GetObject)
#
# v11 removes:
#   - comments/    (ADD_COMMENT tool gone)
#   - archive/qna/ (ARCHIVE_QNA auto-archive gone)
# Both were core to the v10 chain but were flagged as unrealistic by
# review (chatbot-as-write-path doesn't exist in real enterprise RAG;
# auto-archiving admin answers back into a searchable KB doesn't either).
#
# Each KB-indexed .md file gets a companion .metadata.json sidecar
# (uploaded as a separate aws_s3_object). Bedrock KB recognises sidecars
# named {originalfile}.metadata.json automatically. The audience attribute
# scaffolding stays in place for future re-tiering, but in v11 every
# indexed document carries audience=public.
# ===================================================================

resource "aws_s3_bucket" "kb_data" {
  bucket        = "bkp-kb-data-${local.cg_id}"
  force_destroy = true

  tags = {
    Name    = "${local.scenario_name}-kb-data"
    Purpose = "kb-document-storage-public-plus-admin-only-staging"
  }
}

resource "aws_s3_bucket_versioning" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb_data" {
  bucket = aws_s3_bucket.kb_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -------------------------------------------------------------------
# Source filesets — computed once per prefix.
#
# public/      : atlas-2023-q2, atlas-2024-q1, atlas-2025-q3, atlas-ops
# admin-only/  : atlas-2026-q2-unreleased (NOT KB-indexed)
# -------------------------------------------------------------------

locals {
  kb_docs_dir = "${path.module}/../assets/kb_docs"

  _kb_docs_public_raw = toset(concat(
    tolist(fileset(local.kb_docs_dir, "atlas-2023-q2/**/*")),
    tolist(fileset(local.kb_docs_dir, "atlas-2024-q1/**/*")),
    tolist(fileset(local.kb_docs_dir, "atlas-2025-q3/**/*")),
    tolist(fileset(local.kb_docs_dir, "atlas-ops/**/*")),
  ))

  kb_docs_public = toset([
    for f in local._kb_docs_public_raw : f
    if !endswith(f, ".metadata.json")
  ])

  _kb_docs_admin_raw = fileset(local.kb_docs_dir, "atlas-2026-q2-unreleased/**/*")
  kb_docs_admin = toset([
    for f in local._kb_docs_admin_raw : f
    if !endswith(f, ".metadata.json")
  ])
}

# -------------------------------------------------------------------
# public/ prefix — KB-indexed past assessment material.
# -------------------------------------------------------------------

resource "aws_s3_object" "kb_docs_public" {
  for_each = local.kb_docs_public

  bucket = aws_s3_bucket.kb_data.id
  key    = "public/${each.value}"
  source = "${local.kb_docs_dir}/${each.value}"
  etag   = filemd5("${local.kb_docs_dir}/${each.value}")

  tags = {
    Name   = "atlas-archive-document"
    Prefix = "public"
  }
}

resource "aws_s3_object" "kb_docs_public_metadata" {
  for_each = local.kb_docs_public

  bucket       = aws_s3_bucket.kb_data.id
  key          = "public/${each.value}.metadata.json"
  content      = jsonencode({ "metadataAttributes" : { "audience" : "public" } })
  content_type = "application/json"

  tags = {
    Name   = "atlas-archive-metadata"
    Prefix = "public"
  }
}

# -------------------------------------------------------------------
# admin-only/ prefix — atlas-2026-q2-unreleased drafts.
#
# INTENTIONALLY not under any KB inclusion prefix (see bedrock.tf).
# Only reachable through GET_ATLAS_REFERENCE Lambda's direct s3:GetObject,
# and only when sessionAttributes.user_role == 'admin'.
# The flag is embedded in atlas-2026-q2-unreleased/gen/web-sql-vault/README.md.
# -------------------------------------------------------------------

resource "aws_s3_object" "kb_docs_admin" {
  for_each = local.kb_docs_admin

  bucket = aws_s3_bucket.kb_data.id
  key    = "admin-only/${each.value}"
  source = "${local.kb_docs_dir}/${each.value}"
  etag   = filemd5("${local.kb_docs_dir}/${each.value}")

  tags = {
    Name   = "${local.scenario_name}-admin-only"
    Prefix = "admin-only"
  }
}
