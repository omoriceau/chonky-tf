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
