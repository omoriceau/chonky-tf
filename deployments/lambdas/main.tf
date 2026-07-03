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

# ==============================================================================
# REMOTE STATE — pull infrastructure from network-rds deployment
# ==============================================================================
data "terraform_remote_state" "network_rds" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/network-rds/terraform.tfstate"
    region = var.region
  }
}

variable "enable_products_layer" {
  type    = bool
  default = false
}

variable "enable_payments_layer" {
  type    = bool
  default = false
}

variable "layer_build_platform" {
  description = "Docker --platform used to build Lambda layer wheels. Must match the compatible_runtimes/architecture of the Lambda functions consuming the layer (x86_64 -> linux/amd64)."
  type        = string
  default     = "linux/amd64"
}

# ==============================================================================
# Use remote state instead of variables - infrastructure values are fetched automatically
# ==============================================================================
locals {
  vpc_id                = data.terraform_remote_state.network_rds.outputs.vpc_id
  subnet_ids            = data.terraform_remote_state.network_rds.outputs.subnet_ids
  rds_security_group_id = data.terraform_remote_state.network_rds.outputs.rds_security_group_id
  db_endpoint           = data.terraform_remote_state.network_rds.outputs.db_address
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
# PRODUCTS API LAMBDA PERMISSION
# ==============================================================================
resource "aws_lambda_permission" "products_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.products.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

# ==============================================================================
# PRODUCTS API INTEGRATION
# ==============================================================================
resource "aws_apigatewayv2_integration" "products" {
  api_id           = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"
  integration_method = "POST"
  payload_format_version = "2.0"
  
  integration_uri    = module.products.function_arn
  credentials_arn    = aws_iam_role.api_gateway.arn
}

resource "aws_apigatewayv2_route" "products" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /products/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.products.id}"
}

resource "aws_apigatewayv2_route" "products_root" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /products"
  target    = "integrations/${aws_apigatewayv2_integration.products.id}"
}

# ==============================================================================
# PAYMENTS API INTEGRATION
# ==============================================================================
resource "aws_apigatewayv2_integration" "payments" {
  api_id           = aws_apigatewayv2_api.this.id
  integration_type = "AWS_PROXY"
  integration_method = "POST"
  payload_format_version = "2.0"
  
  integration_uri    = module.payments_api.function_arn
  credentials_arn    = aws_iam_role.api_gateway.arn
}

resource "aws_apigatewayv2_route" "payments" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /payments/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.payments.id}"
}

resource "aws_apigatewayv2_route" "payments_root" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "ANY /payments"
  target    = "integrations/${aws_apigatewayv2_integration.payments.id}"
}

# ==============================================================================
# PAYMENTS API LAMBDA PERMISSION
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
  name                   = "${var.name_prefix}-vpc-lambda-sg"
  description            = "Security group for Lambdas running in VPC"
  vpc_id                 = local.vpc_id
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
  cidr_blocks       = ["10.0.0.0/16"]
}

resource "aws_security_group_rule" "vpc_lambda_egress_postgres" {
  type              = "egress"
  security_group_id = aws_security_group.vpc_lambda.id
  description       = "PostgreSQL to RDS"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]
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

  layers = var.enable_payments_layer ? [
    aws_lambda_layer_version.payments[0].arn
  ] : []

  environment_variables = {
    STRIPE_INTENT_FUNCTION_ARN = module.stripe_intent.function_arn
    EVENT_BUS_NAME             = var.event_bus_name
    DB_HOST                    = data.terraform_remote_state.network_rds.outputs.db_address
    DB_PORT                    = data.terraform_remote_state.network_rds.outputs.db_port
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
# PAYMENTS API LAMBDA LAYER (Python dependencies - stripe, psycopg2)
# ==============================================================================
resource "null_resource" "build_payments_layer" {
  count = var.enable_payments_layer ? 1 : 0
  
  triggers = {
    requirements = filemd5("${var.payments_layer_source_dir}/payments_api/requirements.txt")
  }

  provisioner "local-exec" {
    working_dir = path.module
    command = <<-EOT
      set -e
      LAYER_DIR=".build/payments-layer-tmp"
      OUTPUT_ZIP=".build/payments-layer.zip"
      BUILD_DIR="$(pwd)"
      REQ_FILE="$(cd ${var.payments_layer_source_dir}/payments_api && pwd)/requirements.txt"
      
      sudo rm -rf "$LAYER_DIR"
      mkdir -p "$LAYER_DIR/python"
      
      # Build in Amazon Linux 2 Docker container to match Lambda environment
      docker run --rm --user $(id -u):$(id -g) --entrypoint /bin/bash -v "$BUILD_DIR":/work -v "$REQ_FILE":/req.txt public.ecr.aws/lambda/python:3.12 \
        -c "pip install -q -t /work/$LAYER_DIR/python -r /req.txt --no-cache-dir --break-system-packages 2>&1 | grep -v 'does not take into account' || true"
      
      # Create the zip
      cd "$LAYER_DIR"
      zip -q -r "../$(basename $OUTPUT_ZIP)" .
      cd "$BUILD_DIR"
      sudo rm -rf "$LAYER_DIR"
    EOT
  }
}

resource "aws_lambda_layer_version" "payments" {
  count               = var.enable_payments_layer ? 1 : 0
  filename            = "${path.module}/.build/payments-layer.zip"
  layer_name          = "${var.name_prefix}-payments-layer-${var.env}"
  compatible_runtimes = ["python3.12"]
  
  depends_on = [null_resource.build_payments_layer]
}

# ==============================================================================
# PRODUCTS API LAMBDA LAYER (Python dependencies) - Optional
# ==============================================================================
resource "null_resource" "build_products_layer" {
  count = var.enable_products_layer ? 1 : 0
  
  triggers = {
    requirements = filemd5("${var.products_layer_source_dir}/products/requirements.txt")
  }

  provisioner "local-exec" {
    working_dir = path.module
    command = <<-EOT
      set -e
      LAYER_DIR=".build/products-layer-tmp"
      OUTPUT_ZIP=".build/products-layer.zip"
      BUILD_DIR="$(pwd)"
      REQ_FILE="$(cd ${var.products_layer_source_dir}/products && pwd)/requirements.txt"
      
      sudo rm -rf "$LAYER_DIR"
      mkdir -p "$LAYER_DIR/python"
      
      # Build in Amazon Linux 2 Docker container to match Lambda environment
      docker run --rm --user $(id -u):$(id -g) --entrypoint /bin/bash -v "$BUILD_DIR":/work -v "$REQ_FILE":/req.txt public.ecr.aws/lambda/python:3.12 \
        -c "pip install -q -t /work/$LAYER_DIR/python -r /req.txt --no-cache-dir --break-system-packages 2>&1 | grep -v 'does not take into account' || true"
      
      # Create the zip
      cd "$LAYER_DIR"
      zip -q -r "../$(basename $OUTPUT_ZIP)" .
      cd "$BUILD_DIR"
      sudo rm -rf "$LAYER_DIR"
    EOT
  }
}

resource "aws_lambda_layer_version" "products" {
  count               = var.enable_products_layer ? 1 : 0
  filename            = "${path.module}/.build/products-layer.zip"
  layer_name          = "${var.name_prefix}-products-layer-${var.env}"
  compatible_runtimes = ["python3.12"]
  
  depends_on = [null_resource.build_products_layer]
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
    DB_HOST        = data.terraform_remote_state.network_rds.outputs.db_address
    DB_PORT        = data.terraform_remote_state.network_rds.outputs.db_port
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