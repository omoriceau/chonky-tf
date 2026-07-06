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
  description = "Path to the JSON seed data file"
  type        = string
  default     = "dynamodb-seed.json"
}
