variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role, as owner/name"
  type        = string
  default     = "omoriceau/chonkycat-be"
}

variable "chonkycat_admin_repo" {
  description = "chonkycat-admin GitHub repo allowed to assume the admin deploy role, as owner/name"
  type        = string
  default     = "omoriceau/chonkycat-admin"
}
