variable "env" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_user" {
  description = "Database user"
  type        = string
}

variable "event_bus_name" {
  description = "EventBridge event bus name"
  type        = string
}

variable "stripe_intent_source_dir" {
  description = "Path to Stripe intent Lambda source code"
  type        = string
}

variable "payments_api_source_dir" {
  description = "Path to Payments API Lambda source code"
  type        = string
}

variable "payments_layer_source_dir" {
  description = "Path to Payments Lambda layer dependencies (python package)"
  type        = string
}

variable "products_source_dir" {
  description = "Path to Products API Lambda source code"
  type        = string
}

variable "products_layer_source_dir" {
  description = "Path to Products Lambda layer dependencies (python package)"
  type        = string
}

variable "cors_allow_origins" {
  description = "Allowed CORS origins for the API Gateway"
  type        = list(string)
  default     = ["*"]
}