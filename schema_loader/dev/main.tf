terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket  = "chonky-tfstate-dev"
    key     = "schema_loader/dev/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.region
}

# ==============================================================================
# REMOTE STATE — pulls vpc_id, subnet, rds sg from env/dev
# ==============================================================================
data "terraform_remote_state" "env" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-dev"
    key    = "env/dev/terraform.tfstate"
    region = "us-east-1"
  }
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
    cidr_blocks = ["0.0.0.0/0"] # lock to your IP if you want
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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
  key_name                    = "chonky" # your .pem

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y postgresql15
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
resource "null_resource" "run_schema" {
  depends_on = [time_sleep.wait_for_ssm]

  provisioner "file" {
    source      = var.schema_sql_path
    destination = "/tmp/01-schema.sql"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/chonky.pem")
      host        = aws_instance.schema_loader.public_ip
    }
  }

  provisioner "file" {
    source      = var.seed_sql_path
    destination = "/tmp/02-seed.sql"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/chonky.pem")
      host        = aws_instance.schema_loader.public_ip
    }
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/chonky.pem")
      host        = aws_instance.schema_loader.public_ip
    }

    inline = [
      "sudo dnf install -y postgresql15",
      "PGPASSWORD='${var.db_pass}' psql -h ${data.terraform_remote_state.env.outputs.db_address} -U ${var.db_user} -d ${var.db_name} -f /tmp/01-schema.sql",
      "PGPASSWORD='${var.db_pass}' psql -h ${data.terraform_remote_state.env.outputs.db_address} -U ${var.db_user} -d ${var.db_name} -f /tmp/02-seed.sql"
    ]
  }
}
