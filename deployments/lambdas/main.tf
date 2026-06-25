terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

variable "enable_products_layer" {
  type    = bool
  default = false
}

variable "enable_payments_layer" {
  type    = bool
  default = false
}

# ==============================================================================
# Use variables directly - infrastructure values must be provided
# ==============================================================================
locals {
  vpc_id                = var.vpc_id
  subnet_ids            = var.subnet_ids
  rds_security_group_id = var.rds_security_group_id
  db_endpoint           = var.db_endpoint
  cors_allow_origins    = var.cors_allow_origins
}

# ==============================================================================
# API GATEWAY
# ==============================================================================
resource "aws_apigatewayv2_api" "this" {
  name          = "${var.name_prefix}-api-${var.env}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = local.cors_allow_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization", "X-Amz-Date", "X-Api-Key"]
  }

  tags = {
    Name        = "${var.name_prefix}-api-${var.env}"
    Environment = var.env
  }
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = var.env
  auto_deploy = true

  tags = {
    Name        = "${var.name_prefix}-api-${var.env}-stage"
    Environment = var.env
  }
}

# ==============================================================================
# API GATEWAY IAM ROLE (for invoking Lambda)
# ==============================================================================
resource "aws_iam_role" "api_gateway" {
  name = "${var.name_prefix}-api-gateway-${var.env}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.name_prefix}-api-gateway-${var.env}-role"
    Environment = var.env
  }
}

resource "aws_iam_role_policy" "api_gateway_lambda" {
  name = "${var.name_prefix}-api-gateway-${var.env}-lambda-policy"
  role = aws_iam_role.api_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          module.products.function_arn,
          "${module.products.function_arn}:*",
          module.payments_api.function_arn,
          "${module.payments_api.function_arn}:*"
        ]
      }
    ]
  })
}

# ==============================================================================
# PRODUCTS API INTEGRATION
# ==============================================================================
# For HTTP API with Lambda, we need to create the integration with proper credentials
# The URI format for Lambda in HTTP API is: arn:aws:apigateway:region:lambda:path/2015-03-31/functions/function-arn/invocations
resource "aws_lambda_permission" "products_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.products.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# ==============================================================================
# PAYMENTS API INTEGRATION
# ==============================================================================
resource "aws_lambda_permission" "payments_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.payments_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# ==============================================================================
# SECURITY GROUP FOR VPC LAMBDAS
# ==============================================================================
resource "aws_security_group" "vpc_lambda" {
  name        = "${var.name_prefix}-vpc-lambda-sg"
  description = "Security group for Lambdas running in VPC"
  vpc_id      = local.vpc_id
  revoke_rules_on_delete = true

  tags = {
    Name        = "${var.name_prefix}-vpc-lambda-sg"
    Environment = var.env
  }
}

resource "aws_security_group_rule" "vpc_lambda_egress_https" {
  type              = "egress"
  security_group_id = aws_security_group.vpc_lambda.id
  description       = "HTTPS to VPC endpoints"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "vpc_lambda_egress_postgres" {
  type              = "egress"
  security_group_id = aws_security_group.vpc_lambda.id
  description       = "PostgreSQL to RDS"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
}

# ==============================================================================
# SECURITY GROUP RULE: Allow Lambda to connect to RDS
# ==============================================================================
resource "aws_security_group_rule" "lambda_to_rds" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_lambda.id
  security_group_id        = local.rds_security_group_id

  description = "Allow Lambda functions to connect to RDS"
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
    STRIPE_SECRET_NAME = "${var.name_prefix}/${var.env}/stripe_secret_key"
  }

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = ["arn:aws:logs:*:*:*"]
    },
    {
      Effect = "Allow"
      Action = ["secretsmanager:GetSecretValue"]
      Resource = [
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/${var.env}/stripe_secret_key*"
      ]
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
    subnet_ids         = local.subnet_ids
    security_group_ids = [aws_security_group.vpc_lambda.id]
  }

  layers = var.enable_products_layer ? [
    aws_lambda_layer_version.products[0].arn
  ] : []

  environment_variables = {
    STRIPE_INTENT_FUNCTION_ARN = module.stripe_intent.function_arn
    EVENT_BUS_NAME             = var.event_bus_name
    DB_HOST                    = split(":", local.db_endpoint)[0]
    DB_PORT                    = split(":", local.db_endpoint)[1]
    DB_NAME                    = var.db_name
    DB_USER                    = var.db_user
  }

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = ["arn:aws:logs:*:*:*"]
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
      Resource = ["arn:aws:events:${var.region}:*:event-bus/${var.event_bus_name}"]
    },
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/${var.env}/db_pass*",
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/${var.env}/stripe_secret_key*"
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity"
      ]
      Resource = ["*"]
    }
  ]
}

data "aws_caller_identity" "current" {}

# ==============================================================================
# PRODUCTS API LAMBDA LAYER (Python dependencies) - Optional
# ==============================================================================
data "archive_file" "products_layer" {
  count       = var.enable_products_layer ? 1 : 0
  type        = "zip"
  source_dir  = var.products_layer_source_dir
  output_path = "${path.module}/.build/products-layer.zip"
}

resource "aws_lambda_layer_version" "products" {
  count               = var.enable_products_layer ? 1 : 0
  filename            = var.enable_products_layer ? data.archive_file.products_layer[0].output_path : null
  layer_name          = "${var.name_prefix}-products-layer-${var.env}"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = var.enable_products_layer ? data.archive_file.products_layer[0].output_base64sha256 : null
}

# ==============================================================================
# PAYMENTS API LAMBDA LAYER (Python dependencies - stripe, psycopg2)
# ==============================================================================
data "archive_file" "payments_layer" {
  count       = var.enable_payments_layer ? 1 : 0
  type        = "zip"
  source_dir  = var.payments_layer_source_dir
  output_path = "${path.module}/.build/payments-layer.zip"
}

resource "aws_lambda_layer_version" "payments" {
  count               = var.enable_payments_layer ? 1 : 0
  filename            = data.archive_file.payments_layer[0].output_path
  layer_name          = "${var.name_prefix}-payments-layer-${var.env}"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = data.archive_file.payments_layer[0].output_base64sha256
}

# ==============================================================================
# PRODUCTS API LAMBDA (In VPC - database access)
# ==============================================================================
module "products" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "products-api"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  source_dir = var.products_source_dir

  vpc_config = {
    subnet_ids         = local.subnet_ids
    security_group_ids = [aws_security_group.vpc_lambda.id]
  }

  layers = var.enable_products_layer ? [
    aws_lambda_layer_version.products[0].arn
  ] : []

  environment_variables = {
    EVENT_BUS_NAME = var.event_bus_name
    DB_HOST        = split(":", local.db_endpoint)[0]
    DB_PORT        = split(":", local.db_endpoint)[1]
    DB_NAME        = var.db_name
    DB_USER        = var.db_user
  }

  policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = ["arn:aws:logs:*:*:*"]
    },
    {
      Effect = "Allow"
      Action = [
        "events:PutEvents"
      ]
      Resource = ["arn:aws:events:${var.region}:*:event-bus/${var.event_bus_name}"]
    },
    {
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name_prefix}/${var.env}/db_pass*"
      ]
    },
    {
      Effect = "Allow"
      Action = [
        "sts:GetCallerIdentity"
      ]
      Resource = ["*"]
    }
  ]
}
