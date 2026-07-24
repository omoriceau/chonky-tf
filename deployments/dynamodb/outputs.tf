output "users_table_name" {
  description = "Users table name"
  value       = aws_dynamodb_table.users.name
}

output "users_table_arn" {
  description = "Users table ARN"
  value       = aws_dynamodb_table.users.arn
}

output "products_table_name" {
  description = "Products table name"
  value       = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  description = "Products table ARN"
  value       = aws_dynamodb_table.products.arn
}

output "orders_table_name" {
  description = "Orders table name"
  value       = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  description = "Orders table ARN"
  value       = aws_dynamodb_table.orders.arn
}

output "payments_table_name" {
  description = "Payments table name"
  value       = aws_dynamodb_table.payments.name
}

output "payments_table_arn" {
  description = "Payments table ARN"
  value       = aws_dynamodb_table.payments.arn
}

output "promotions_table_name" {
  description = "Promotions table name"
  value       = aws_dynamodb_table.promotions.name
}

output "promotions_table_arn" {
  description = "Promotions table ARN"
  value       = aws_dynamodb_table.promotions.arn
}

output "table_arns" {
  description = "All table ARNs, for building IAM policies"
  value = [
    aws_dynamodb_table.users.arn,
    "${aws_dynamodb_table.users.arn}/index/*",
    aws_dynamodb_table.products.arn,
    "${aws_dynamodb_table.products.arn}/index/*",
    aws_dynamodb_table.orders.arn,
    "${aws_dynamodb_table.orders.arn}/index/*",
    aws_dynamodb_table.payments.arn,
    "${aws_dynamodb_table.payments.arn}/index/*",
    aws_dynamodb_table.promotions.arn,
    "${aws_dynamodb_table.promotions.arn}/index/*",
  ]
}
