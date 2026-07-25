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

resource "aws_secretsmanager_secret" "stripe_key" {
  name        = "${var.name_prefix}/${var.env}/stripe_secret_key"
  description = "Stripe secret key"
}

resource "aws_secretsmanager_secret_version" "stripe_key" {
  secret_id     = aws_secretsmanager_secret.stripe_key.id
  secret_string = var.stripe_secret_key
}