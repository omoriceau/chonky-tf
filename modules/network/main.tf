data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.name_prefix}-vpc"
    Environment = var.env
  }
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "${var.name_prefix}-subnet-a"
    Environment = var.env
  }
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name        = "${var.name_prefix}-subnet-b"
    Environment = var.env
  }
}

# ==============================================================================
# INTERNET GATEWAY
# ==============================================================================
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.name_prefix}-igw"
    Environment = var.env
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.name_prefix}-public-rt"
    Environment = var.env
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.public.id
}

# ==============================================================================
# VPC ENDPOINT SECURITY GROUP
# ==============================================================================
resource "aws_security_group" "vpc_endpoints" {
  name                   = "${var.name_prefix}-vpc-endpoints-sg"
  description            = "Security group for VPC endpoints (Lambda, Secrets Manager, Events)"
  vpc_id                 = aws_vpc.this.id
  revoke_rules_on_delete = true

  tags = {
    Name        = "${var.name_prefix}-vpc-endpoints-sg"
    Environment = var.env
  }
}

resource "aws_security_group_rule" "vpc_endpoints_ingress_https" {
  type              = "ingress"
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from VPC"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "vpc_endpoints_egress_https" {
  type              = "egress"
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS to AWS services"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ==============================================================================
# VPC ENDPOINTS
# ==============================================================================
# Lambda service endpoint
resource "aws_vpc_endpoint" "lambda" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.lambda"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.a.id, aws_subnet.b.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.name_prefix}-lambda-endpoint"
    Environment = var.env
  }
}

# Secrets Manager endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.a.id, aws_subnet.b.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.name_prefix}-secretsmanager-endpoint"
    Environment = var.env
  }
}

# EventBridge (Events) endpoint
resource "aws_vpc_endpoint" "events" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.events"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.a.id, aws_subnet.b.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.name_prefix}-events-endpoint"
    Environment = var.env
  }
}

# STS endpoint
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = [aws_subnet.a.id, aws_subnet.b.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name        = "${var.name_prefix}-sts-endpoint"
    Environment = var.env
  }
}

# Data source to get current region
data "aws_region" "current" {}