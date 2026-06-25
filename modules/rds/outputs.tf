output "db_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "RDS database address (host)"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS database port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.this.db_name
}

output "db_user" {
  description = "Database master username"
  value       = aws_db_instance.this.username
  sensitive   = true
}

output "security_group_id" {
  description = "Security group ID for the database"
  value       = aws_security_group.db.id
}
