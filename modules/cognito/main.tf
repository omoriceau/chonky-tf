data "aws_region" "current" {}

resource "aws_cognito_user_pool" "this" {
  name = "${var.name_prefix}-${var.pool_name}-${var.env}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = var.password_minimum_length
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  mfa_configuration = var.mfa_configuration

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = var.allow_admin_create_user_only
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = {
    Name        = "${var.name_prefix}-${var.pool_name}-${var.env}"
    Environment = var.env
  }
}

# Default explicit_auth_flows (ALLOW_ADMIN_USER_PASSWORD_AUTH) suits the
# customers pool: the users lambda drives signup/login via Admin* API calls
# (AdminCreateUser/AdminSetUserPassword) under its own IAM role, not the
# client-side SRP flow. A Hosted UI consumer (like the admins pool) instead
# needs ALLOW_USER_SRP_AUTH — see var.explicit_auth_flows overrides below.
resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.name_prefix}-${var.pool_name}-${var.env}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false

  explicit_auth_flows = var.explicit_auth_flows

  access_token_validity  = var.access_token_validity_minutes
  refresh_token_validity = var.refresh_token_validity_days

  token_validity_units {
    access_token  = "minutes"
    refresh_token = "days"
  }

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  supported_identity_providers = ["COGNITO"]

  # Only set when enable_hosted_ui_domain is true — these three go together
  # (allowed_oauth_flows requires allowed_oauth_flows_user_pool_client, and
  # both are meaningless without a Hosted UI domain to redirect through).
  allowed_oauth_flows                  = var.enable_hosted_ui_domain ? ["code"] : null
  allowed_oauth_scopes                 = var.enable_hosted_ui_domain ? var.allowed_oauth_scopes : null
  allowed_oauth_flows_user_pool_client = var.enable_hosted_ui_domain
}

resource "aws_cognito_user_pool_domain" "this" {
  count = var.enable_hosted_ui_domain ? 1 : 0

  domain       = var.hosted_ui_domain_prefix
  user_pool_id = aws_cognito_user_pool.this.id
}
