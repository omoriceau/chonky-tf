variable "env" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "stripe_secret_key" {
  type      = string
  sensitive = true
}

variable "stripe_webhook_secret" {
  type      = string
  sensitive = true
}