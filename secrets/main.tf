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

resource "aws_secretsmanager_secret" "db_pass" {
  name        = "${var.name_prefix}/${var.env}/db_pass"
  description = "RDS master password"
}

resource "aws_secretsmanager_secret_version" "db_pass" {
  secret_id     = aws_secretsmanager_secret.db_pass.id
  secret_string = var.db_pass
}

resource "aws_secretsmanager_secret" "stripe_key" {
  name        = "${var.name_prefix}/${var.env}/stripe_secret_key"
  description = "Stripe secret key"
}

resource "aws_secretsmanager_secret_version" "stripe_key" {
  secret_id     = aws_secretsmanager_secret.stripe_key.id
  secret_string = var.stripe_secret_key
}

resource "aws_secretsmanager_secret" "ssh_private_key" {
  name        = "${var.name_prefix}/${var.env}/ssh_private_key"
  description = "SSH private key for schema loader EC2"
}

resource "aws_secretsmanager_secret_version" "ssh_private_key" {
  secret_id     = aws_secretsmanager_secret.ssh_private_key.id
  secret_string = var.ssh_private_key
}