terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ==============================================================================
# SES DOMAIN IDENTITY — verifies var.domain_name for sending. dev and prod
# verify different domains (dev.chonkycat.ca vs chonkycat.ca), same pattern as
# deployments/custom-domain (api2.chonkycat.ca dev vs api.chonkycat.ca prod),
# so the two envs never fight over one shared AWS-account-scoped SES identity.
# ==============================================================================
module "ses" {
  source = "../../modules/ses"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  domain_name          = var.domain_name
  cloudflare_zone_id   = var.cloudflare_zone_id
  cloudflare_api_token = var.cloudflare_api_token

  sandbox_test_recipients          = var.sandbox_test_recipients
  enable_bounce_complaint_tracking = var.enable_bounce_complaint_tracking
  admin_alert_email                = var.admin_alert_email
}
