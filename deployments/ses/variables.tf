variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "chonky"
}

variable "domain_name" {
  description = "Domain to verify as an SES identity (e.g. chonkycat.ca for prod, dev.chonkycat.ca for dev)"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone.DNS edit permission for the relevant zone"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for chonkycat.ca (found on the zone's Overview page in the Cloudflare dashboard)"
  type        = string
}

variable "sandbox_test_recipients" {
  description = "Email addresses to verify as SES identities so they can receive mail while the account is in SES sandbox mode (e.g. the DEV_EMAIL redirect target)"
  type        = list(string)
  default     = []
}

variable "enable_bounce_complaint_tracking" {
  description = "Whether to create SNS topics + a configuration set wired to SES bounce/complaint events"
  type        = bool
  default     = true
}

variable "admin_alert_email" {
  description = "Email address to subscribe to the bounce/complaint SNS topics for alerting. Empty string disables the subscription."
  type        = string
  default     = ""
}
