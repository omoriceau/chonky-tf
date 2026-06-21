terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chonky-tfstate-dev"
    key            = "env/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "chonky-tfstate-lock-dev"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

module "network" {
  source = "../../modules/network"

  env           = var.env
  name_prefix   = var.name_prefix
  vpc_cidr      = var.vpc_cidr
  subnet_a_cidr = var.subnet_a_cidr
  subnet_b_cidr = var.subnet_b_cidr
}

module "rds" {
  source = "../../modules/rds"

  env         = var.env
  name_prefix = var.name_prefix

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.subnet_ids

  db_name                 = var.db_name
  db_user                 = var.db_user
  db_pass                 = var.db_pass
  instance_class          = var.instance_class
  engine_version          = var.engine_version
  allocated_storage       = var.allocated_storage
  backup_retention_period = var.backup_retention_period
}

# ==============================================================================
# SECURITY GROUP FOR VPC LAMBDAS
# ==============================================================================
resource "aws_security_group" "vpc_lambda" {
  name        = "${var.name_prefix}-vpc-lambda-sg"
  description = "Security group for Lambdas running in VPC"
  vpc_id      = module.network.vpc_id

  egress {
    description = "HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "PostgreSQL to RDS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "${var.name_prefix}-vpc-lambda-sg"
    Environment = var.env
  }
}

# ==============================================================================
# STRIPE INTENT LAMBDA (External - NOT in VPC)
# ==============================================================================
module "stripe_intent" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "stripe-intent"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  source_dir = var.stripe_intent_source_dir

  environment_variables = {
    STRIPE_SECRET_KEY = var.stripe_secret_key
  }

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }
  ]
}

# ==============================================================================
# PAYMENTS API LAMBDA (In VPC - can call Stripe Lambda)
# ==============================================================================
module "payments_api" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "payments-api"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  source_dir = var.payments_api_source_dir

  vpc_config = {
    subnet_ids         = module.network.subnet_ids
    security_group_ids = [aws_security_group.vpc_lambda.id]
  }

  environment_variables = {
    STRIPE_SECRET_KEY              = var.stripe_secret_key
    STRIPE_INTENT_FUNCTION_ARN     = module.stripe_intent.function_arn
    EVENT_BUS_NAME                 = var.event_bus_name
    DB_ENDPOINT                    = module.rds.endpoint
    DB_NAME                        = var.db_name
    DB_USER                        = var.db_user
    DB_PASSWORD                    = var.db_pass
  }

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    },
    {
      Effect = "Allow"
      Action = [
        "lambda:InvokeFunction"
      ]
      Resource = [
        module.stripe_intent.function_arn,
        "${module.stripe_intent.function_arn}:*"
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "events:PutEvents"
      ]
      Resource = "arn:aws:events:${var.region}:*:event-bus/${var.event_bus_name}"
    },
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = "arn:aws:secretsmanager:${var.region}:*:secret:*"
    },
    {
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity"
      ]
      Resource = "*"
    }
  ]
}
