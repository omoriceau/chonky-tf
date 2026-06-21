output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "subnet_a_id" {
  description = "ID of subnet A"
  value       = aws_subnet.a.id
}

output "subnet_b_id" {
  description = "ID of subnet B"
  value       = aws_subnet.b.id
}

output "subnet_ids" {
  description = "List of both subnet IDs"
  value       = [aws_subnet.a.id, aws_subnet.b.id]
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.this.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "lambda_endpoint_id" {
  description = "Lambda VPC endpoint ID"
  value       = aws_vpc_endpoint.lambda.id
}

output "secretsmanager_endpoint_id" {
  description = "Secrets Manager VPC endpoint ID"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "events_endpoint_id" {
  description = "Events (EventBridge) VPC endpoint ID"
  value       = aws_vpc_endpoint.events.id
}

output "sts_endpoint_id" {
  description = "STS VPC endpoint ID"
  value       = aws_vpc_endpoint.sts.id
}
