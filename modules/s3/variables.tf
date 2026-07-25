variable "name_prefix" {
  description = "App Name prefix"
  type        = string
}

variable "env" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "bucket_suffix" {
  description = "Suffix to make the bucket name unique"
  type        = string
}

variable "block_public_acls" {
  description = "Block public ACLs on the bucket"
  type        = bool
  default     = true
}

variable "ignore_public_acls" {
  description = "Ignore public ACLs on the bucket"
  type        = bool
  default     = true
}

variable "block_public_policy" {
  description = "Block public bucket policies. Set false only for buckets that intentionally serve public content (e.g. via a scoped bucket policy)."
  type        = bool
  default     = true
}

variable "restrict_public_buckets" {
  description = "Restrict public bucket policies to those granted by AWS services. Set false only for buckets that intentionally serve public content."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete this bucket even if it (or its object versions) aren't empty. Default false so state/data buckets can't be destroyed by accident."
  type        = bool
  default     = false
}