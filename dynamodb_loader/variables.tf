variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "state_env" {
  description = "Env suffix for the tfstate bucket name (chonky-tfstate-<state_env>). Defaults to matching `env`, but can diverge — e.g. production uses bucket \"chonky-tfstate-prod\" since \"chonky-tfstate-production\" is a globally squatted name owned by another AWS account."
  type        = string
  default     = "dev"
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
