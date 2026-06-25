resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Firewall for ${var.name_prefix} database"
  vpc_id      = var.vpc_id
  revoke_rules_on_delete = true

  tags = {
    Name        = "${var.name_prefix}-db-sg"
    Environment = var.env
  }
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name_prefix}-subnet-group"
  description = "Subnet group for ${var.name_prefix} database"
  subnet_ids  = var.subnet_ids

  tags = {
    Name        = "${var.name_prefix}-subnet-group"
    Environment = var.env
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-instance"
  instance_class = var.instance_class
  engine         = "postgres"
  engine_version = var.engine_version

  db_name  = var.db_name
  username = var.db_user
  password = var.db_pass

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period    = var.backup_retention_period
  multi_az                   = false
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.final_snapshot_identifier

  tags = {
    Name        = "${var.name_prefix}-instance"
    Environment = var.env
  }
}
