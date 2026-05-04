terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}

data "aws_caller_identity" "current" {}

resource "random_id" "cg_id" {
  byte_length = 4
}

locals {
  # Keeping scenario_name = atlas_kb_v10 to allow incremental v10 -> v11 apply
  # without recreating OpenSearch Serverless (~10min) or the KB. The v11 design
  # changes are all about removing ADD_COMMENT/ARCHIVE_QNA paths and adding the
  # Cognito Identity Pool federated-role IAM drift; nothing in those changes
  # requires renaming the underlying scenario string.
  scenario_name = "atlas_kb_v10"
  scenario_ver  = "v11"
  cg_id         = random_id.cg_id.hex
  default_tags = {
    Scenario  = local.scenario_name
    Version   = local.scenario_ver
    CgId      = local.cg_id
    ManagedBy = "terraform"
  }
}
