output "domain" {
  description = "The verified SES domain"
  value       = aws_ses_domain_identity.this.domain
}

output "domain_identity_arn" {
  description = "ARN of the SES domain identity, scoped to this project's domain only"
  value       = aws_ses_domain_identity.this.arn
}

output "no_reply_address" {
  description = "Customer-facing sender address (orders, newsletter)"
  value       = "no-reply@${aws_ses_domain_identity.this.domain}"
}

output "admin_address" {
  description = "Internal notification sender/support address"
  value       = "admin@${aws_ses_domain_identity.this.domain}"
}

output "configuration_set_name" {
  description = "SES configuration set name to pass as SES_CONFIGURATION_SET"
  value       = aws_sesv2_configuration_set.this.configuration_set_name
}

output "bounce_topic_arn" {
  description = "SNS topic ARN for SES bounce notifications"
  value       = var.enable_bounce_complaint_tracking ? aws_sns_topic.bounces[0].arn : null
}

output "complaint_topic_arn" {
  description = "SNS topic ARN for SES complaint notifications"
  value       = var.enable_bounce_complaint_tracking ? aws_sns_topic.complaints[0].arn : null
}
