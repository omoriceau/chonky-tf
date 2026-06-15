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
