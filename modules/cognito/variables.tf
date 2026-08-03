variable "name_prefix" {
  description = "App name prefix"
  type        = string
}

variable "env" {
  description = "Environment name (dev, production)"
  type        = string
}

variable "pool_name" {
  description = "Distinguishes this pool from others in the same account (e.g. \"customers\", \"admins\")"
  type        = string
}

variable "password_minimum_length" {
  description = "Minimum password length enforced by the pool"
  type        = number
  default     = 8
}

variable "mfa_configuration" {
  description = "MFA requirement for the pool: OFF, ON, or OPTIONAL"
  type        = string
  default     = "OFF"
}

variable "callback_urls" {
  description = "Allowed OAuth callback URLs for the app client (only needed if hosted-UI/OAuth flows are used)"
  type        = list(string)
  default     = []
}

variable "logout_urls" {
  description = "Allowed OAuth logout URLs for the app client (only needed if hosted-UI/OAuth flows are used)"
  type        = list(string)
  default     = []
}

variable "access_token_validity_minutes" {
  description = "Access token validity, in minutes"
  type        = number
  default     = 60
}

variable "refresh_token_validity_days" {
  description = "Refresh token validity, in days"
  type        = number
  default     = 30
}

variable "allow_admin_create_user_only" {
  description = "Disable public self-signup — users can only be created via Admin* API calls"
  type        = bool
  default     = false
}

variable "explicit_auth_flows" {
  description = "Auth flows enabled on the app client (e.g. ALLOW_USER_SRP_AUTH for Hosted UI, ALLOW_ADMIN_USER_PASSWORD_AUTH for server-driven signup/login)"
  type        = list(string)
  default     = ["ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

variable "enable_hosted_ui_domain" {
  description = "Create a Cognito Hosted UI domain and enable the authorization-code OAuth flow on the app client"
  type        = bool
  default     = false
}

variable "hosted_ui_domain_prefix" {
  description = "Domain prefix for the Hosted UI (<prefix>.auth.<region>.amazoncognito.com) — globally unique across all AWS accounts in the region. Required if enable_hosted_ui_domain is true."
  type        = string
  default     = ""
}

variable "allowed_oauth_scopes" {
  description = "OAuth scopes for the app client, only used when enable_hosted_ui_domain is true"
  type        = list(string)
  default     = ["openid", "email", "profile"]
}
