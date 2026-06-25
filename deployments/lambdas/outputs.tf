output "stripe_intent_function_arn" {
  description = "ARN of the Stripe Intent Lambda function"
  value       = module.stripe_intent.function_arn
}

output "stripe_intent_function_name" {
  description = "Name of the Stripe Intent Lambda function"
  value       = module.stripe_intent.function_name
}

output "payments_api_function_arn" {
  description = "ARN of the Payments API Lambda function"
  value       = module.payments_api.function_arn
}

output "payments_api_function_name" {
  description = "Name of the Payments API Lambda function"
  value       = module.payments_api.function_name
}

output "products_function_arn" {
  description = "ARN of the Products API Lambda function"
  value       = module.products.function_arn
}

output "products_function_name" {
  description = "Name of the Products API Lambda function"
  value       = module.products.function_name
}

output "vpc_lambda_security_group_id" {
  description = "Security group ID for VPC Lambdas"
  value       = aws_security_group.vpc_lambda.id
}

output "api_gateway_endpoint" {
  description = "HTTP API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.this.id
}
