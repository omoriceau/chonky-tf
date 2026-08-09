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
  description = "Env suffix for the tfstate bucket name (chonky-tfstate-<state_env>) used to look up the cognito remote state. Defaults to matching `env`, but can diverge — e.g. production uses bucket \"chonky-tfstate-prod\" since \"chonky-tfstate-production\" is a globally squatted name owned by another AWS account."
  type        = string
  default     = ""
}

variable "customer_cognito_pool_id" {
  description = "Pins the customer Cognito pool id instead of reading it from cognito's remote state. Needed where the customer pool is owned by chonky-cat-fe's Amplify Gen2 backend rather than the deployments/cognito Terraform stack (e.g. production) — remote state won't have a customers_user_pool_id output in that case. Leave empty to fall back to remote state (e.g. dev, where deployments/cognito does own the customer pool)."
  type        = string
  default     = ""
}

variable "customer_cognito_client_id" {
  description = "Pins the customer Cognito app client id instead of reading it from cognito's remote state. See customer_cognito_pool_id."
  type        = string
  default     = ""
}

variable "dev_email" {
  description = "DevEmail parameter passed to deploy-products.sh (SES sandbox test recipient)"
  type        = string
  default     = "dev@example.com"
}

variable "ses_domain" {
  description = "Domain to verify in SES for sending notification emails (--ses-domain). Leave empty to skip SES setup entirely."
  type        = string
  default     = ""
}

variable "repo_url" {
  description = "chonky-cat-be git URL. SSH form, not HTTPS — the repo is private and this is pulled non-interactively (local-exec), so it relies on the deploying machine's own SSH key/agent rather than prompting for credentials."
  type        = string
  default     = "git@github.com:omoriceau/chonkycat-be.git"
}

variable "branch" {
  description = "Branch to pull and deploy"
  type        = string
  default     = "master"
}

variable "checkout_dir" {
  description = "Local path to check chonky-cat-be out into for deploys. Leave empty to default to a .be-checkout/ directory alongside this module — kept separate from any developer's own working clone of the repo, since this one gets reset --hard on every apply."
  type        = string
  default     = ""
}

variable "force_redeploy" {
  description = "Change this value to force a redeploy even when chonky-cat-be's master hasn't moved (e.g. after a manual stack fix)"
  type        = string
  default     = ""
}

variable "api_domain_name" {
  description = "Custom domain to attach to the API Gateway. Leave empty to default to \"api.chonkycat.ca\" for env = production, or \"<env>-api.chonkycat.ca\" otherwise."
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone.DNS edit permission for chonkycat.ca. Custom domain setup (ACM cert + API Gateway domain + CNAME) is skipped entirely — see outputs.api_custom_domain_status — if this or cloudflare_zone_id is empty."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for chonkycat.ca. See cloudflare_api_token."
  type        = string
  default     = ""
}
