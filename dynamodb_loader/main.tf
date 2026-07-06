terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

# ==============================================================================
# REMOTE STATE — pulls table names from the dynamodb deployment.
# Adjust the `key` below if your dynamodb stack's state path differs.
# ==============================================================================
data "terraform_remote_state" "dynamodb" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/dynamodb/terraform.tfstate"
    region = var.region
  }
}

# ==============================================================================
# SEED — no VPC/EC2/SSH needed here, unlike the old RDS schema_loader:
# DynamoDB is a public AWS API endpoint, so local-exec can reach it directly
# from wherever `terraform apply` runs (be it a laptop or a CI runner with
# AWS credentials).
#
# Triggers re-run the seed whenever the script or the seed data changes,
# and it's safe to re-run any time — seed.py derives deterministic ids from
# each row's natural key (email/sku), so re-seeding overwrites the same
# items in place instead of creating duplicates.
# ==============================================================================
resource "null_resource" "seed" {
  triggers = {
    seed_script_hash = filesha256("${path.module}/seed.py")
    seed_data_hash   = filesha256(var.seed_data_path)
    users_table      = data.terraform_remote_state.dynamodb.outputs.users_table_name
    products_table   = data.terraform_remote_state.dynamodb.outputs.products_table_name
    promotions_table = data.terraform_remote_state.dynamodb.outputs.promotions_table_name
  }

  provisioner "local-exec" {
    command     = "pip install -r requirements.txt --quiet --break-system-packages && python3 seed.py ${var.seed_data_path}"
    working_dir = path.module

    environment = {
      USERS_TABLE      = data.terraform_remote_state.dynamodb.outputs.users_table_name
      PRODUCTS_TABLE   = data.terraform_remote_state.dynamodb.outputs.products_table_name
      PROMOTIONS_TABLE = data.terraform_remote_state.dynamodb.outputs.promotions_table_name
      AWS_REGION       = var.region
    }
  }
}
