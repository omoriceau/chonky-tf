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

variable "event_bus_name" {
  description = "EventBridge event bus name. Matches chonky-cat-be's template.yaml default (\"chonkychonk-bus\") intentionally: SAM's deploy-products.sh only creates the bus imperatively if it doesn't already exist, so terraform owning it here is safe and lets both deployment paths share one bus."
  type        = string
  default     = "chonkychonk-bus"
}

variable "dev_email" {
  description = "Email address for receiving test emails in SES Sandbox mode (dev environment)"
  type        = string
  default     = "dev@example.com"
}

variable "cognito_enabled" {
  description = "Whether the Users lambda should be granted Cognito admin permissions and passed a pool id"
  type        = bool
  default     = true
}

variable "stripe_secret_key_secret_name" {
  description = "Secrets Manager secret name holding the Stripe secret key (see secrets/main.tf)"
  type        = string
  default     = null
}

variable "stripe_webhook_secret_name" {
  description = "Secrets Manager secret name holding the Stripe webhook signing secret (see secrets/main.tf)"
  type        = string
  default     = null
}

variable "cors_allow_origin" {
  description = "Value for Access-Control-Allow-Origin on API Gateway CORS preflight responses. \"*\" is only appropriate for dev (mirrors the --cors flag in chonky-cat-be/deploy-products.sh, which refuses anything but dev)."
  type        = string
  default     = "*"
}

# ==============================================================================
# Lambda source directories — all point into the chonky-cat-be checkout,
# which lives as a sibling directory to this one.
# ==============================================================================
variable "products_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/products"
}

variable "orders_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/orders"
}

variable "users_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/users"
}

variable "payments_api_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/payments_api"
}

variable "stripe_intent_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/stripe_intent"
}

variable "stripe_webhook_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/stripe_webhook"
}

variable "email_service_source_dir" {
  type    = string
  default = "../../../chonky-cat-be/lambdas/email_service"
}

variable "shared_layer_source_dir" {
  description = "Path to the shared/python layer content (shared.cors, shared.events, etc.)"
  type        = string
  default     = "../../../chonky-cat-be/shared/python"
}

# ==============================================================================
# Dependency layers — pip-installed via Docker (to match the Lambda runtime)
# for the two function groups that need packages beyond boto3.
# ==============================================================================
variable "enable_stripe_layer" {
  description = "Build the stripe_deps layer (stripe SDK) for stripe_intent/stripe_webhook via Docker. Disable only if Docker isn't available and those two functions are being managed out of band."
  type        = bool
  default     = true
}

variable "stripe_layer_requirements_dir" {
  description = "Directory containing the requirements.txt to build the stripe_deps layer from"
  type        = string
  default     = "../../../chonky-cat-be/lambdas/stripe_intent"
}

variable "enable_products_deps_layer" {
  description = "Build the products_deps layer (python-ulid, typing_extensions) via Docker."
  type        = bool
  default     = true
}

variable "products_layer_requirements_dir" {
  description = "Directory containing the requirements.txt to build the products_deps layer from"
  type        = string
  default     = "../../../chonky-cat-be/lambdas/products"
}

variable "layer_build_platform" {
  description = "Docker --platform used to build Lambda layer wheels. Must match the Lambda functions' architecture (x86_64 -> linux/amd64)."
  type        = string
  default     = "linux/amd64"
}
