# ==============================================================================
# DATA ARCHIVE FOR LAMBDA CODE
# ==============================================================================
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.terraform/${var.function_name}.zip"
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
# VPC EXECUTION POLICY (if VPC config provided)
# ==============================================================================
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count      = var.vpc_config != null ? 1 : 0
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
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
  filename            = data.archive_file.lambda.output_path
  function_name       = "${var.name_prefix}-${var.function_name}-${var.env}"
  role                = aws_iam_role.lambda_role.arn
  handler             = var.handler
  source_code_hash    = data.archive_file.lambda.output_base64sha256
  timeout             = var.timeout
  memory_size         = var.memory_size
  runtime             = var.runtime
  layers              = var.layers
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = var.environment_variables
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  tags = {
    Name        = "${var.name_prefix}-${var.function_name}-${var.env}"
    Environment = var.env
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_execution
  ]
}

# ==============================================================================
# LAMBDA PERMISSION FOR INVOKE (optional, added via separate resource if needed)
# ==============================================================================
# This would be created when another Lambda or service needs to invoke this one
