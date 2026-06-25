variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "chonky"
}

variable "db_name" {
  description = "Database name to run SQL against"
  type        = string
  default     = "chonkydb"
}

variable "db_user" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "schema_sql_path" {
  description = "Local path to schema SQL file"
  type        = string
  default     = "../../sql-data/01-schema.sql"
}

variable "seed_sql_path" {
  description = "Local path to seed data SQL file"
  type        = string
  default     = "../../sql-data/02-init-data.sql"
}

# schema_loader/variables.tf
variable "key_name" {
  description = "EC2 Key Pair name for SSH access to schema loader"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key contents for schema loader EC2"
  type        = string
  sensitive   = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH to schema loader"
  type        = string
  default     = "0.0.0.0/0" # override this — never leave as default
}