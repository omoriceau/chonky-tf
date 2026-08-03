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

variable "seed_data_path" {
  description = "Path to the JSON seed data file (products drive the sku -> image mapping)"
  type        = string
  default     = "../dynamodb_loader/dynamodb-seed.json"
}

variable "base_imgs_dir" {
  description = "Directory of category base images (wet.jpg, dry.jpg, treat.jpg)"
  type        = string
  default     = "base_imgs"
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
