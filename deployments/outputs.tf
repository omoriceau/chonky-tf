output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = module.network.subnet_ids
}

output "db_endpoint" {
  description = "RDS database endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_address" {
  description = "RDS database address (host only)"
  value       = module.rds.db_address
}

output "db_port" {
  description = "RDS database port"
  value       = module.rds.db_port
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = module.rds.security_group_id
}

output "subnet_a_id" {
  description = "First subnet ID"
  value       = module.network.subnet_a_id
}

output "subnet_b_id" {
  description = "First subnet ID"
  value       = module.network.subnet_b_id
}

output "stripe_intent_function_arn" {
  description = "Stripe Intent Lambda ARN"
  value       = module.stripe_intent.function_arn
}

output "stripe_intent_function_name" {
  description = "Stripe Intent Lambda name"
  value       = module.stripe_intent.function_name
}

output "payments_api_function_arn" {
  description = "Payments API Lambda ARN"
  value       = module.payments_api.function_arn
}

output "payments_api_function_name" {
  description = "Payments API Lambda name"
  value       = module.payments_api.function_name
}

output "vpc_lambda_security_group_id" {
  description = "VPC Lambda security group ID"
  value       = aws_security_group.vpc_lambda.id
}

