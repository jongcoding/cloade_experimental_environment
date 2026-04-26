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
  scenario_name = "atlas_kb_v10"
  cg_id         = random_id.cg_id.hex
  default_tags = {
    Scenario  = local.scenario_name
    CgId      = local.cg_id
    ManagedBy = "terraform"
  }
}
