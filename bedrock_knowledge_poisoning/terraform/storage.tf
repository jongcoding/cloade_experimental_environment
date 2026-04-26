# ===================================================================
# S3 Bucket for Bedrock Knowledge Base data source (v10)
#
# Single bucket, four prefixes:
#   public/      Atlas Tech past assessments + ops SOPs (KB-indexed)
#   comments/    engineer contributions (KB-indexed, ADD_COMMENT target)
#   archive/qna/ auto-archived chat Q&A (KB-indexed, ARCHIVE_QNA target)
#   admin-only/  atlas-2026-q2-unreleased drafts (NOT KB-indexed;
#                admin-only via GET_ATLAS_REFERENCE direct S3 GetObject)
#
# Each KB-indexed .md file gets a companion .metadata.json sidecar
# (uploaded as a separate aws_s3_object). Bedrock KB recognises sidecars
# named {originalfile}.metadata.json automatically.
# The audience attribute in the sidecar drives the metadata filter that
# separates employee_agent and admin_agent retrieve scopes.
# ===================================================================

resource "aws_s3_bucket" "kb_data" {
  bucket        = "bkp-kb-data-${local.cg_id}"
  force_destroy = true

  tags = {
    Name    = "${local.scenario_name}-kb-data"
    Purpose = "KB-document-storage-plus-comments-plus-QnA-archive-plus-admin-staging"
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
# comments/    : assets/kb_docs/comments/**
# archive/     : assets/kb_docs/archive/**
# admin-only/  : assets/kb_docs/atlas-2026-q2-unreleased/** (NOT KB-indexed)
# -------------------------------------------------------------------

locals {
  kb_docs_dir = "${path.module}/../assets/kb_docs"

  # Gather raw filesets, then strip any pre-existing .metadata.json files
  # so we do not upload them twice (Terraform creates them dynamically below).
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

  _kb_docs_comments_raw = fileset(local.kb_docs_dir, "comments/**/*")
  kb_docs_comments = toset([
    for f in local._kb_docs_comments_raw : f
    if !endswith(f, ".metadata.json")
  ])

  _kb_docs_archive_raw = fileset(local.kb_docs_dir, "archive/**/*")
  kb_docs_archive = toset([
    for f in local._kb_docs_archive_raw : f
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
# comments/ prefix — seeded engineer comments.
# Keys already contain "comments/" so no additional prefix.
# -------------------------------------------------------------------

resource "aws_s3_object" "kb_docs_comments" {
  for_each = local.kb_docs_comments

  bucket = aws_s3_bucket.kb_data.id
  key    = each.value
  source = "${local.kb_docs_dir}/${each.value}"
  etag   = filemd5("${local.kb_docs_dir}/${each.value}")

  tags = {
    Name   = "${local.scenario_name}-comment"
    Prefix = "comments"
  }
}

resource "aws_s3_object" "kb_docs_comments_metadata" {
  for_each = local.kb_docs_comments

  bucket       = aws_s3_bucket.kb_data.id
  key          = "${each.value}.metadata.json"
  content      = jsonencode({ "metadataAttributes" : { "audience" : "employee" } })
  content_type = "application/json"

  tags = {
    Name   = "${local.scenario_name}-comment-metadata"
    Prefix = "comments"
  }
}

# -------------------------------------------------------------------
# archive/qna/ prefix — seeded past Q&A transcripts.
# -------------------------------------------------------------------

resource "aws_s3_object" "kb_docs_archive" {
  for_each = local.kb_docs_archive

  bucket = aws_s3_bucket.kb_data.id
  key    = each.value
  source = "${local.kb_docs_dir}/${each.value}"
  etag   = filemd5("${local.kb_docs_dir}/${each.value}")

  tags = {
    Name   = "${local.scenario_name}-qna-archive"
    Prefix = "archive"
  }
}

resource "aws_s3_object" "kb_docs_archive_metadata" {
  for_each = local.kb_docs_archive

  bucket       = aws_s3_bucket.kb_data.id
  key          = "${each.value}.metadata.json"
  content      = jsonencode({ "metadataAttributes" : { "audience" : "public" } })
  content_type = "application/json"

  tags = {
    Name   = "${local.scenario_name}-qna-archive-metadata"
    Prefix = "archive"
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
