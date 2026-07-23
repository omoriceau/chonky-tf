output "api_gateway_id" {
  description = "REST API Gateway ID"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_gateway_stage_name" {
  description = "REST API Gateway stage name"
  value       = aws_api_gateway_stage.this.stage_name
}

output "api_gateway_invoke_url" {
  description = "Base invoke URL for the REST API Gateway stage"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "products_api" {
  description = "Products endpoint"
  value       = "${aws_api_gateway_stage.this.invoke_url}/products"
}

output "users_api" {
  description = "Users endpoint"
  value       = "${aws_api_gateway_stage.this.invoke_url}/users"
}

output "orders_api" {
  description = "Orders (shopping cart) endpoint"
  value       = "${aws_api_gateway_stage.this.invoke_url}/orders"
}

output "payments_api" {
  description = "Payments endpoint"
  value       = "${aws_api_gateway_stage.this.invoke_url}/payments"
}

output "webhook_api" {
  description = "Stripe webhook endpoint"
  value       = "${aws_api_gateway_stage.this.invoke_url}/webhook"
}

output "event_bus_name" {
  description = "EventBridge bus name"
  value       = aws_cloudwatch_event_bus.this.name
}

output "event_bus_arn" {
  description = "EventBridge bus ARN"
  value       = aws_cloudwatch_event_bus.this.arn
}

output "products_function_arn" {
  value = module.products.function_arn
}

output "orders_function_arn" {
  value = module.orders.function_arn
}

output "users_function_arn" {
  value = module.users.function_arn
}

output "payments_api_function_arn" {
  value = module.payments_api.function_arn
}

output "stripe_intent_function_arn" {
  value = module.stripe_intent.function_arn
}

output "stripe_webhook_function_arn" {
  value = module.stripe_webhook.function_arn
}

output "email_service_function_arn" {
  value = module.email_service.function_arn
}
