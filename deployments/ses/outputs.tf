output "domain" {
  description = "The verified SES domain"
  value       = module.ses.domain
}

output "domain_identity_arn" {
  description = "ARN of the SES domain identity"
  value       = module.ses.domain_identity_arn
}

output "no_reply_address" {
  description = "Customer-facing sender address (orders, newsletter)"
  value       = module.ses.no_reply_address
}

output "admin_address" {
  description = "Internal notification sender/support address"
  value       = module.ses.admin_address
}

output "configuration_set_name" {
  description = "SES configuration set name to pass as SES_CONFIGURATION_SET"
  value       = module.ses.configuration_set_name
}

output "bounce_topic_arn" {
  description = "SNS topic ARN for SES bounce notifications"
  value       = module.ses.bounce_topic_arn
}

output "complaint_topic_arn" {
  description = "SNS topic ARN for SES complaint notifications"
  value       = module.ses.complaint_topic_arn
}
