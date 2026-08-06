output "admins_user_pool_id" {
  description = "Admins user pool ID"
  value       = module.admins.user_pool_id
}

output "admins_user_pool_arn" {
  description = "Admins user pool ARN"
  value       = module.admins.user_pool_arn
}

output "admins_app_client_id" {
  description = "Admins app client ID"
  value       = module.admins.app_client_id
}

output "admins_hosted_ui_domain" {
  description = "Admins pool Hosted UI domain — set as VITE_COGNITO_DOMAIN in chonky-cat-admin"
  value       = module.admins.hosted_ui_domain
}
