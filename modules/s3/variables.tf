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