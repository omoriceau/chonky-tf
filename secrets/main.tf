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

resource "aws_secretsmanager_secret" "stripe_webhook" {
  name        = "${var.name_prefix}/${var.env}/stripe_webhook_secret"
  description = "Stripe webhook signing secret"
}

resource "aws_secretsmanager_secret_version" "stripe_webhook" {
  secret_id     = aws_secretsmanager_secret.stripe_webhook.id
  secret_string = var.stripe_webhook_secret
}

resource "aws_secretsmanager_secret" "stripe_publish_key" {
  name        = "${var.name_prefix}/${var.env}/stripe_publish_key"
  description = "Stripe publishable key"
}

resource "aws_secretsmanager_secret_version" "stripe_publish_key" {
  secret_id     = aws_secretsmanager_secret.stripe_publish_key.id
  secret_string = var.stripe_publish_key
}
