terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }

  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

# ==============================================================================
# REMOTE STATE — pulls vpc_id, subnet, rds sg from env/<env>
# ==============================================================================
data "terraform_remote_state" "env" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/network-rds/terraform.tfstate"
    region = var.region
  }
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = "${var.name_prefix}/${var.env}/db_pass"
}

data "aws_secretsmanager_secret_version" "ssh_private_key" {
  secret_id = "${var.name_prefix}/${var.env}/ssh_private_key"
}

# ==============================================================================
# DATA
# ==============================================================================
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ==============================================================================
# IAM — allows EC2 to register with SSM (no SSH keys needed)
# ==============================================================================
resource "aws_iam_role" "ssm" {
  name = "${var.name_prefix}-schema-loader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.name_prefix}-schema-loader-role"
    Environment = var.env
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.name_prefix}-schema-loader-profile"
  role = aws_iam_role.ssm.name
}

resource "aws_iam_role_policy" "schema_loader_secrets" {
  name = "${var.name_prefix}-schema-loader-secrets"
  role = aws_iam_role.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.region}:*:secret:${var.name_prefix}/${var.env}/db_pass*"
    }]
  })
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================
resource "aws_security_group" "schema_loader" {
  name   = "${var.name_prefix}-schema-loader-sg"
  vpc_id = data.terraform_remote_state.env.outputs.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Allow outbound to RDS
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTPS for package downloads and AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow outbound HTTP for package downloads
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Punch a hole in the RDS security group for this EC2
resource "aws_security_group_rule" "rds_from_schema_loader" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = data.terraform_remote_state.env.outputs.rds_security_group_id
  source_security_group_id = aws_security_group.schema_loader.id
  description              = "Allow schema loader EC2 to connect to RDS"
}

# ==============================================================================
# EC2
# ==============================================================================
# EC2 — add key_name and public IP
resource "aws_instance" "schema_loader" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = data.terraform_remote_state.env.outputs.subnet_b_id
  vpc_security_group_ids      = [aws_security_group.schema_loader.id]
  associate_public_ip_address = true
  key_name                    = var.name_prefix

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Update the system
    dnf update -y

    # Install PostgreSQL 15 client
    dnf install -y postgresql18

    # Verify psql is available (fail fast if not)
    psql --version
  EOF

  tags = {
    Name        = "${var.name_prefix}-schema-loader"
    Environment = var.env
  }
}

# ==============================================================================
# WAIT FOR SSM — EC2 needs time after boot before SSM is reachable
# ==============================================================================
resource "time_sleep" "wait_for_ssm" {
  depends_on      = [aws_instance.schema_loader]
  create_duration = "120s"
}

# ==============================================================================
# RUN SQL via SSM — fires once on apply, torn down with destroy
# ==============================================================================
resource "null_resource" "upload_sql" {
  depends_on = [time_sleep.wait_for_ssm]

  provisioner "file" {
    source      = var.schema_sql_path
    destination = "/tmp/01-schema.sql"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = data.aws_secretsmanager_secret_version.ssh_private_key.secret_string
      host        = aws_instance.schema_loader.public_ip
    }
  }

  provisioner "file" {
    source      = var.seed_sql_path
    destination = "/tmp/02-seed.sql"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = data.aws_secretsmanager_secret_version.ssh_private_key.secret_string
      host        = aws_instance.schema_loader.public_ip
    }
  }
}

resource "null_resource" "run_schema" {
  depends_on = [null_resource.upload_sql]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = data.aws_secretsmanager_secret_version.ssh_private_key.secret_string
      host        = aws_instance.schema_loader.public_ip
    }

    inline = [
      "cloud-init status --wait",
      "sudo dnf install -y postgresql15",
      "export DB_PASS='${data.aws_secretsmanager_secret_version.db.secret_string}'",
      "PGPASSWORD=$DB_PASS psql -h ${data.terraform_remote_state.env.outputs.db_address} -U ${var.db_user} -d ${var.db_name} -f /tmp/01-schema.sql || exit 1"
    ]
  }
}

resource "null_resource" "run_seed" {
  depends_on = [null_resource.run_schema]

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = data.aws_secretsmanager_secret_version.ssh_private_key.secret_string
      host        = aws_instance.schema_loader.public_ip
    }

    inline = [
      "export DB_PASS='${data.aws_secretsmanager_secret_version.db.secret_string}'",
      "PGPASSWORD=$DB_PASS psql -h ${data.terraform_remote_state.env.outputs.db_address} -U ${var.db_user} -d ${var.db_name} -f /tmp/02-seed.sql || exit 1"
    ]
  }
}