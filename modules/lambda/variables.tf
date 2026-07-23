variable "env" {
  description = "Environment name"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "function_name" {
  description = "Lambda function name (without prefix)"
  type        = string
}

variable "handler" {
  description = "Lambda handler (e.g., lambda_handler.lambda_handler)"
  type        = string
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.13"
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Lambda memory in MB"
  type        = number
  default     = 256
}

variable "environment_variables" {
  description = "Environment variables for the Lambda"
  type        = map(string)
  default     = {}
}

variable "source_dir" {
  description = "Path to Lambda source code directory"
  type        = string
}

variable "excludes" {
  description = "Relative paths within source_dir to exclude from the deployment zip (e.g. tests, __pycache__)"
  type        = list(string)
  default     = []
}

variable "layers" {
  description = "Lambda layer ARNs"
  type        = list(string)
  default     = []
}

variable "policy_statements" {
  description = "Additional IAM policy statements for the Lambda role"
  type        = list(any)
  default     = []
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions"
  type        = number
  default     = -1
}
