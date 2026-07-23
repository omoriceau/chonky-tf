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

# ==============================================================================
# CUSTOMERS POOL — storefront (chonky-cat-fe) signup/login. Wired into the
# backend's Users lambda today (deployments/lambdas).
# ==============================================================================
module "customers" {
  source = "../../modules/cognito"

  name_prefix = var.name_prefix
  env         = var.env
  pool_name   = "customers"

  callback_urls = var.customers_callback_urls
  logout_urls   = var.customers_logout_urls
}

# ==============================================================================
# ADMINS POOL — chonky-cat-admin logs in from a different domain than the
# storefront, so it gets its own pool (isolated blast radius, independent
# app-client config). Backs the admin app's Cognito Hosted UI login
# (react-oidc-context, authorization-code + PKCE) — self-signup is disabled
# since this is an internal tool; logins are seeded below via aws_cognito_user.
# ==============================================================================
module "admins" {
  source = "../../modules/cognito"

  name_prefix = var.name_prefix
  env         = var.env
  pool_name   = "admins"

  callback_urls = var.admins_callback_urls
  logout_urls   = var.admins_logout_urls

  allow_admin_create_user_only = true
  explicit_auth_flows          = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  enable_hosted_ui_domain      = true
  hosted_ui_domain_prefix      = local.admins_hosted_ui_domain_prefix
}

locals {
  admins_hosted_ui_domain_prefix = coalesce(var.admins_hosted_ui_domain_prefix, "${var.name_prefix}-admin-${var.env}")
}

# ==============================================================================
# Admin logins — AdminCreateUser, matching how scripts/push-to-prod.sh in
# chonky-cat-admin seeds a login today. Cognito auto-generates a temporary
# password and emails it (desired_delivery_mediums = EMAIL) since neither
# password nor temporary_password is set here. Add addresses to
# var.admin_emails (e.g. in dev.tfvars) to get a login created on apply;
# leaving it empty creates none.
# ==============================================================================
resource "aws_cognito_user" "admin" {
  for_each = toset(var.admin_emails)

  user_pool_id = module.admins.user_pool_id
  username     = each.value

  attributes = {
    email          = each.value
    email_verified = true
  }

  desired_delivery_mediums = ["EMAIL"]
}
