terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

# Fetch the DB password from Secrets Manager
data "aws_secretsmanager_secret_version" "db_pass" {
  secret_id = "${var.name_prefix}/${var.env}/db_pass"
}

module "network" {
  source = "../../modules/network"

  env           = var.env
  name_prefix   = var.name_prefix
  vpc_cidr      = var.vpc_cidr
  subnet_a_cidr = var.subnet_a_cidr
  subnet_b_cidr = var.subnet_b_cidr
}

module "rds" {
  source = "../../modules/rds"

  env         = var.env
  name_prefix = var.name_prefix

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.subnet_ids

  db_name                   = var.db_name
  db_user                   = var.db_user
  db_pass                   = data.aws_secretsmanager_secret_version.db_pass.secret_string
  instance_class            = var.instance_class
  engine_version            = var.engine_version
  allocated_storage         = var.allocated_storage
  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier
}