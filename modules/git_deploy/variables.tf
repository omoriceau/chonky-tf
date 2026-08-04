variable "repo_url" {
  description = "Git URL to clone (SSH form — pulled non-interactively via local-exec, so it relies on the deploying machine's own SSH key/agent rather than prompting for credentials)"
  type        = string
}

variable "branch" {
  description = "Branch to pull and deploy"
  type        = string
  default     = "master"
}

variable "checkout_dir" {
  description = "Local path to check the repo out into. Reset --hard on every apply — never point this at a developer's own working clone."
  type        = string
}

variable "deploy_command" {
  description = "Shell command run with checkout_dir as its working directory after the checkout is refreshed"
  type        = string
}

variable "force_redeploy" {
  description = "Change this value to force a redeploy even when nothing else about the checkout/deploy inputs has changed"
  type        = string
  default     = ""
}

variable "env_vars" {
  description = "Environment variables passed through to deploy_command"
  type        = map(string)
  default     = {}
}
