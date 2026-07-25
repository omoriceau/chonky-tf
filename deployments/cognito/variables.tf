variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "customers_callback_urls" {
  description = "OAuth callback URLs for the customers app client (only needed if hosted-UI/OAuth flows are used)"
  type        = list(string)
  default     = []
}

variable "customers_logout_urls" {
  description = "OAuth logout URLs for the customers app client"
  type        = list(string)
  default     = []
}

variable "admins_callback_urls" {
  description = "OAuth callback URLs for the admins app client"
  type        = list(string)
  default     = []
}

variable "admins_logout_urls" {
  description = "OAuth logout URLs for the admins app client"
  type        = list(string)
  default     = []
}

variable "admins_hosted_ui_domain_prefix" {
  description = "Hosted UI domain prefix for the admins pool (<prefix>.auth.<region>.amazoncognito.com) — globally unique across all AWS accounts in the region. Defaults to \"<name_prefix>-admin-<env>\" if unset."
  type        = string
  default     = null
}

variable "admin_emails" {
  description = "Email addresses to seed as admin logins (AdminCreateUser) in the admins pool. Cognito emails each one a temporary password."
  type        = list(string)
  default     = []
}

variable "default_admin_email" {
  description = "Email/username for a default admin login seeded with a fixed permanent password (default_admin_password) instead of an emailed temporary one. Leave empty to skip."
  type        = string
  default     = ""
}

variable "default_admin_password" {
  description = "Permanent password for default_admin_email. Must satisfy the admins pool's password policy (min length, upper/lower/number)."
  type        = string
  default     = ""
  sensitive   = true
}
