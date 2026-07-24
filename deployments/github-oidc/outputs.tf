output "github_actions_deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN secret on the chonkycat-be GitHub repo"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_deploy_admin_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN secret on the chonkycat-admin GitHub repo"
  value       = aws_iam_role.github_actions_deploy_admin.arn
}
