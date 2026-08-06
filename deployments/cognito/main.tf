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

# Only referenced by the Hosted UI domain prefix default below.
data "aws_caller_identity" "current" {}

# ==============================================================================
# No customers pool here — the storefront (chonky-cat-fe) owns its own
# customer-facing Cognito pool via its Amplify Gen2 backend
# (amplify/auth/resource.ts), not this module. This module only provisions
# the admins pool below; chonky-cat-be's CustomerCognitoUserPoolId /
# CustomerCognitoAppClientId (samconfig.toml) point directly at the
# Amplify-managed pool's id/client, not at anything from here.
# ==============================================================================

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
  # Hosted UI domain prefixes are globally unique across ALL AWS accounts in
  # a region (like S3 bucket names) — "chonky-admin-production" and a
  # follow-up disambiguator both turned out to already be squatted by other
  # AWS accounts (2026-08-05). Account-id-suffixed by default so a new
  # environment never has to discover that the hard way; set
  # admins_hosted_ui_domain_prefix explicitly (as production.tfvars does,
  # pinned once chosen — see its own comment on why) to override.
  admins_hosted_ui_domain_prefix = coalesce(
    var.admins_hosted_ui_domain_prefix,
    "${var.name_prefix}-admin-${var.env}-${data.aws_caller_identity.current.account_id}"
  )
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

# ==============================================================================
# Default admin login — fixed permanent password instead of an emailed
# temporary one, for dev convenience (no mailbox needed to get in). Setting
# `password` directly makes the account immediately usable with
# ALLOW_USER_SRP_AUTH; message_action = SUPPRESS skips Cognito's invite
# email, which would otherwise go out even though a real password is set.
# ==============================================================================
resource "aws_cognito_user" "default_admin" {
  count = var.default_admin_email != "" ? 1 : 0

  user_pool_id = module.admins.user_pool_id
  username     = var.default_admin_email

  attributes = {
    email          = var.default_admin_email
    email_verified = true
  }

  password       = var.default_admin_password
  message_action = "SUPPRESS"
}
