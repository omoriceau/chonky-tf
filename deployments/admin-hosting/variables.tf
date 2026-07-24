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

variable "domain_name" {
  description = "Domain the admin SPA is served at"
  type        = string
  default     = "admin.chonkycat.ca"
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
