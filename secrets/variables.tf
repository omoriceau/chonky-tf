variable "env" { type = string }
variable "region" { type = string }
variable "name_prefix" { type = string }

variable "stripe_secret_key" {
  type      = string
  sensitive = true
}

#variable "db_pass" {
#  type      = string
#  sensitive = true
#}

#variable "ssh_private_key" {
#  type      = string
#  sensitive = true
#}