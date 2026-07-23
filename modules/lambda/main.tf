terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ==============================================================================
# DATA ARCHIVE FOR LAMBDA CODE
# ==============================================================================
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.terraform/${var.function_name}.zip"
  excludes    = var.excludes
}

# ==============================================================================
# IAM ROLE FOR LAMBDA
# ==============================================================================
resource "aws_iam_role" "lambda_role" {
  name = "${var.name_prefix}-${var.function_name}-${var.env}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.name_prefix}-${var.function_name}-${var.env}-role"
    Environment = var.env
  }
}

# ==============================================================================
# BASIC EXECUTION POLICY (CloudWatch Logs)
# ==============================================================================
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ==============================================================================
# ADDITIONAL POLICY STATEMENTS
# ==============================================================================
resource "aws_iam_role_policy" "lambda_custom_policy" {
  count = length(var.policy_statements) > 0 ? 1 : 0
  name  = "${var.name_prefix}-${var.function_name}-${var.env}-policy"
  role  = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = var.policy_statements
  })
}

# ==============================================================================
# LAMBDA FUNCTION
# ==============================================================================
resource "aws_lambda_function" "this" {
  filename                       = data.archive_file.lambda.output_path
  function_name                  = "${var.name_prefix}-${var.function_name}-${var.env}"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = var.handler
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  timeout                        = var.timeout
  memory_size                    = var.memory_size
  runtime                        = var.runtime
  layers                         = var.layers
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = var.environment_variables
  }

  tags = {
    Name        = "${var.name_prefix}-${var.function_name}-${var.env}"
    Environment = var.env
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
}

