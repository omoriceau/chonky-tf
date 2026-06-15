terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chonky-tfstate-dev"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "chonky-tfstate-lock-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

module "network" {
  source = "../../modules/network"

  env         = var.env
  name_prefix = var.name_prefix
  vpc_cidr    = var.vpc_cidr
  subnet_a_cidr = var.subnet_a_cidr
  subnet_b_cidr = var.subnet_b_cidr
}

module "rds" {
  source = "../../modules/rds"

  env         = var.env
  name_prefix = var.name_prefix

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.subnet_ids

  db_name                 = var.db_name
  db_user                 = var.db_user
  db_pass                 = var.db_pass
  instance_class          = var.instance_class
  engine_version          = var.engine_version
  allocated_storage       = var.allocated_storage
  backup_retention_period = var.backup_retention_period
}
