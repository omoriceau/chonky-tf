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

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_a_cidr" {
  description = "CIDR block for subnet A"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_b_cidr" {
  description = "CIDR block for subnet B"
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "chonkydb"
}

variable "db_user" {
  description = "Master database username"
  type        = string
  default     = "chonky"
  sensitive   = true
}

variable "db_pass" {
  description = "Master database password"
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "stripe_secret_key" {
  description = "Stripe secret API key"
  type        = string
  sensitive   = true
}

variable "event_bus_name" {
  description = "EventBridge event bus name"
  type        = string
  default     = "chonkychonk-bus"
}

variable "stripe_intent_source_dir" {
  description = "Path to stripe_intent Lambda source code"
  type        = string
}

variable "payments_api_source_dir" {
  description = "Path to payments_api Lambda source code"
  type        = string
}

