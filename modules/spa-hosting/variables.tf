variable "name_prefix" {
  description = "App name prefix"
  type        = string
}

variable "env" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "domain_name" {
  description = "CloudFront alias / custom domain the SPA is served at"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name. Defaults to domain_name if unset (must be globally unique)."
  type        = string
  default     = null
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for domain_name — must be in us-east-1, CloudFront requires it regardless of the deployment's region"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}
