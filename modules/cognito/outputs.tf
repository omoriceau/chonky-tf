output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "hosted_ui_domain" {
  description = "Full Hosted UI domain (null unless enable_hosted_ui_domain is true)"
  value       = var.enable_hosted_ui_domain ? "https://${aws_cognito_user_pool_domain.this[0].domain}.auth.${data.aws_region.current.region}.amazoncognito.com" : null
}
