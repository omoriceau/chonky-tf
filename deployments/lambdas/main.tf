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

data "aws_caller_identity" "current" {}

# ==============================================================================
# REMOTE STATE — DynamoDB tables and Cognito pools this stack depends on.
# ==============================================================================
data "terraform_remote_state" "dynamodb" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/dynamodb/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "cognito" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/cognito/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "ses" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/ses/terraform.tfstate"
    region = var.region
  }
}

locals {
  stripe_secret_key_secret_name = coalesce(var.stripe_secret_key_secret_name, "${var.name_prefix}/${var.env}/stripe_secret_key")
  stripe_webhook_secret_name    = coalesce(var.stripe_webhook_secret_name, "${var.name_prefix}/${var.env}/stripe_webhook_secret")

  cognito_user_pool_id  = var.cognito_enabled ? data.terraform_remote_state.cognito.outputs.customers_user_pool_id : ""
  cognito_user_pool_arn = var.cognito_enabled ? data.terraform_remote_state.cognito.outputs.customers_user_pool_arn : null

  users_table_arn      = data.terraform_remote_state.dynamodb.outputs.users_table_arn
  products_table_arn   = data.terraform_remote_state.dynamodb.outputs.products_table_arn
  orders_table_arn     = data.terraform_remote_state.dynamodb.outputs.orders_table_arn
  payments_table_arn   = data.terraform_remote_state.dynamodb.outputs.payments_table_arn
  promotions_table_arn = data.terraform_remote_state.dynamodb.outputs.promotions_table_arn

  # Env vars applied to every function, matching template.yaml's Globals.Function.Environment.
  common_env = {
    EVENT_BUS_NAME                = aws_cloudwatch_event_bus.this.name
    STRIPE_SECRET_KEY_SECRET_NAME = local.stripe_secret_key_secret_name
    STRIPE_WEBHOOK_SECRET_NAME    = local.stripe_webhook_secret_name
    ENVIRONMENT                   = var.env
    DEV_EMAIL                     = var.dev_email
    EMAIL_FROM_ADDRESS            = data.terraform_remote_state.ses.outputs.no_reply_address
    EMAIL_FROM_NAME               = "ChonkyChonk"
    SUPPORT_EMAIL                 = data.terraform_remote_state.ses.outputs.admin_address
    SES_CONFIGURATION_SET         = data.terraform_remote_state.ses.outputs.configuration_set_name
  }

  dynamodb_crud_actions = [
    "dynamodb:GetItem",
    "dynamodb:DeleteItem",
    "dynamodb:PutItem",
    "dynamodb:Scan",
    "dynamodb:Query",
    "dynamodb:UpdateItem",
    "dynamodb:BatchWriteItem",
    "dynamodb:BatchGetItem",
    "dynamodb:DescribeTable",
    "dynamodb:ConditionCheckItem",
  ]

  dynamodb_read_actions = [
    "dynamodb:GetItem",
    "dynamodb:Query",
    "dynamodb:Scan",
    "dynamodb:BatchGetItem",
    "dynamodb:DescribeTable",
  ]

  logs_statement = {
    Effect = "Allow"
    Action = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    Resource = ["arn:aws:logs:*:*:*"]
  }
}

# ==============================================================================
# EVENTBRIDGE BUS — shared by orders, users, and email_service.
# ==============================================================================
resource "aws_cloudwatch_event_bus" "this" {
  name = var.event_bus_name

  tags = {
    Name        = var.event_bus_name
    Environment = var.env
  }
}

# ==============================================================================
# SHARED LAYER — shared.cors / shared.events, pure python, no external deps
# (shared/db.py's psycopg2 import is dead code: nothing in the current
# lambdas imports shared.db, so no pip/Docker build is needed here).
# ==============================================================================
data "archive_file" "shared_layer" {
  type        = "zip"
  source_dir  = var.shared_layer_source_dir
  output_path = "${path.module}/.build/shared-layer.zip"
}

resource "aws_lambda_layer_version" "shared" {
  filename            = data.archive_file.shared_layer.output_path
  source_code_hash    = data.archive_file.shared_layer.output_base64sha256
  layer_name          = "${var.name_prefix}-shared-${var.env}"
  compatible_runtimes = ["python3.13"]
}

# ==============================================================================
# STRIPE DEPS LAYER — stripe SDK, used by stripe_intent + stripe_webhook.
# ==============================================================================
resource "null_resource" "build_stripe_layer" {
  count = var.enable_stripe_layer ? 1 : 0

  triggers = {
    requirements = filemd5("${var.stripe_layer_requirements_dir}/requirements.txt")
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = <<-EOT
      set -e
      LAYER_DIR=".build/stripe-layer-tmp"
      OUTPUT_ZIP=".build/stripe-layer.zip"
      BUILD_DIR="$(pwd)"
      REQ_FILE="$(cd ${var.stripe_layer_requirements_dir} && pwd)/requirements.txt"

      rm -rf "$LAYER_DIR"
      mkdir -p "$LAYER_DIR/python"

      docker run --rm --platform ${var.layer_build_platform} --user $(id -u):$(id -g) --entrypoint /bin/bash -v "$BUILD_DIR":/work -v "$REQ_FILE":/req.txt public.ecr.aws/lambda/python:3.13 \
        -c "pip install -q -t /work/$LAYER_DIR/python -r /req.txt --no-cache-dir --break-system-packages 2>&1 | grep -v 'does not take into account' || true"

      cd "$LAYER_DIR"
      zip -q -r "../$(basename $OUTPUT_ZIP)" .
      cd "$BUILD_DIR"
      rm -rf "$LAYER_DIR"
    EOT
  }
}

resource "aws_lambda_layer_version" "stripe_deps" {
  count               = var.enable_stripe_layer ? 1 : 0
  filename            = "${path.module}/.build/stripe-layer.zip"
  layer_name          = "${var.name_prefix}-stripe-deps-${var.env}"
  compatible_runtimes = ["python3.13"]

  depends_on = [null_resource.build_stripe_layer]
}

# ==============================================================================
# PRODUCTS DEPS LAYER — python-ulid, typing_extensions.
# ==============================================================================
resource "null_resource" "build_products_layer" {
  count = var.enable_products_deps_layer ? 1 : 0

  triggers = {
    requirements = filemd5("${var.products_layer_requirements_dir}/requirements.txt")
  }

  provisioner "local-exec" {
    working_dir = path.module
    command     = <<-EOT
      set -e
      LAYER_DIR=".build/products-layer-tmp"
      OUTPUT_ZIP=".build/products-layer.zip"
      BUILD_DIR="$(pwd)"
      REQ_FILE="$(cd ${var.products_layer_requirements_dir} && pwd)/requirements.txt"

      rm -rf "$LAYER_DIR"
      mkdir -p "$LAYER_DIR/python"

      docker run --rm --platform ${var.layer_build_platform} --user $(id -u):$(id -g) --entrypoint /bin/bash -v "$BUILD_DIR":/work -v "$REQ_FILE":/req.txt public.ecr.aws/lambda/python:3.13 \
        -c "pip install -q -t /work/$LAYER_DIR/python -r /req.txt --no-cache-dir --break-system-packages 2>&1 | grep -v 'does not take into account' || true"

      cd "$LAYER_DIR"
      zip -q -r "../$(basename $OUTPUT_ZIP)" .
      cd "$BUILD_DIR"
      rm -rf "$LAYER_DIR"
    EOT
  }
}

resource "aws_lambda_layer_version" "products_deps" {
  count               = var.enable_products_deps_layer ? 1 : 0
  filename            = "${path.module}/.build/products-layer.zip"
  layer_name          = "${var.name_prefix}-products-deps-${var.env}"
  compatible_runtimes = ["python3.13"]

  depends_on = [null_resource.build_products_layer]
}

# ==============================================================================
# LAMBDA FUNCTIONS
# ==============================================================================

module "products" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "products"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.products_source_dir
  excludes   = ["tests", "__pycache__", "requirements-dev.txt", "pytest.ini"]

  layers = concat(
    [aws_lambda_layer_version.shared.arn],
    var.enable_products_deps_layer ? [aws_lambda_layer_version.products_deps[0].arn] : []
  )

  environment_variables = merge(local.common_env, {
    PRODUCTS_TABLE_NAME = data.terraform_remote_state.dynamodb.outputs.products_table_name
  })

  policy_statements = [
    local.logs_statement,
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.products_table_arn, "${local.products_table_arn}/index/*"]
    },
  ]
}

module "orders" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "orders"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.orders_source_dir
  excludes   = ["__pycache__"]

  layers = [aws_lambda_layer_version.shared.arn]

  environment_variables = merge(local.common_env, {
    ORDERS_TABLE_NAME     = data.terraform_remote_state.dynamodb.outputs.orders_table_name
    PRODUCTS_TABLE_NAME   = data.terraform_remote_state.dynamodb.outputs.products_table_name
    PROMOTIONS_TABLE_NAME = data.terraform_remote_state.dynamodb.outputs.promotions_table_name
  })

  policy_statements = [
    local.logs_statement,
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.orders_table_arn, "${local.orders_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.products_table_arn, "${local.products_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = local.dynamodb_read_actions
      Resource = [local.promotions_table_arn, "${local.promotions_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = ["dynamodb:TransactWriteItems"]
      Resource = [local.orders_table_arn, local.products_table_arn]
    },
    {
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = [aws_cloudwatch_event_bus.this.arn]
    },
  ]
}

module "users" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "users"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.users_source_dir
  excludes   = ["__pycache__"]

  layers = [aws_lambda_layer_version.shared.arn]

  environment_variables = merge(local.common_env, {
    USERS_TABLE_NAME     = data.terraform_remote_state.dynamodb.outputs.users_table_name
    COGNITO_USER_POOL_ID = local.cognito_user_pool_id
    COGNITO_ENABLED      = tostring(var.cognito_enabled)
  })

  policy_statements = concat(
    [
      local.logs_statement,
      {
        Effect   = "Allow"
        Action   = local.dynamodb_crud_actions
        Resource = [local.users_table_arn, "${local.users_table_arn}/index/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:TransactWriteItems"]
        Resource = [local.users_table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = [aws_cloudwatch_event_bus.this.arn]
      },
    ],
    var.cognito_enabled ? [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminSetUserPassword",
          "cognito-idp:AdminDeleteUser",
          "cognito-idp:AdminUpdateUserAttributes",
        ]
        Resource = [local.cognito_user_pool_arn]
      },
    ] : []
  )
}

module "payments_api" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "payments-api"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.payments_api_source_dir
  excludes   = ["__pycache__"]

  layers = [aws_lambda_layer_version.shared.arn]

  environment_variables = merge(local.common_env, {
    STRIPE_INTENT_FUNCTION_ARN = module.stripe_intent.function_arn
    PAYMENTS_TABLE_NAME        = data.terraform_remote_state.dynamodb.outputs.payments_table_name
    ORDERS_TABLE_NAME          = data.terraform_remote_state.dynamodb.outputs.orders_table_name
  })

  policy_statements = [
    local.logs_statement,
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.payments_table_arn, "${local.payments_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.orders_table_arn, "${local.orders_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = ["dynamodb:TransactWriteItems"]
      Resource = [local.payments_table_arn, local.orders_table_arn]
    },
    {
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = [aws_cloudwatch_event_bus.this.arn]
    },
    {
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        module.stripe_intent.function_arn,
        "${module.stripe_intent.function_arn}:*",
      ]
    },
  ]
}

module "stripe_intent" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "stripe-intent"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.stripe_intent_source_dir

  layers = concat(
    [aws_lambda_layer_version.shared.arn],
    var.enable_stripe_layer ? [aws_lambda_layer_version.stripe_deps[0].arn] : []
  )

  environment_variables = local.common_env

  policy_statements = [
    local.logs_statement,
    {
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.stripe_secret_key_secret_name}-*"]
    },
  ]
}

module "stripe_webhook" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "stripe-webhook"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.stripe_webhook_source_dir

  layers = concat(
    [aws_lambda_layer_version.shared.arn],
    var.enable_stripe_layer ? [aws_lambda_layer_version.stripe_deps[0].arn] : []
  )

  environment_variables = merge(local.common_env, {
    PAYMENTS_TABLE_NAME = data.terraform_remote_state.dynamodb.outputs.payments_table_name
    ORDERS_TABLE_NAME   = data.terraform_remote_state.dynamodb.outputs.orders_table_name
  })

  policy_statements = [
    local.logs_statement,
    {
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.stripe_webhook_secret_name}-*"]
    },
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.payments_table_arn, "${local.payments_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = local.dynamodb_crud_actions
      Resource = [local.orders_table_arn, "${local.orders_table_arn}/index/*"]
    },
    {
      Effect   = "Allow"
      Action   = ["dynamodb:TransactWriteItems"]
      Resource = [local.payments_table_arn, local.orders_table_arn]
    },
    {
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = [aws_cloudwatch_event_bus.this.arn]
    },
  ]
}

module "email_service" {
  source = "../../modules/lambda"

  env         = var.env
  name_prefix = var.name_prefix
  region      = var.region

  function_name = "email-service"
  handler       = "lambda_handler.lambda_handler"
  runtime       = "python3.13"

  source_dir = var.email_service_source_dir

  layers = [aws_lambda_layer_version.shared.arn]

  environment_variables = local.common_env

  policy_statements = [
    local.logs_statement,
    {
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = [data.terraform_remote_state.ses.outputs.domain_identity_arn]
    },
  ]
}

# ==============================================================================
# EVENTBRIDGE RULE — routes order/user events to email_service.
# Matches template.yaml's OrderEmailEvent pattern.
# ==============================================================================
resource "aws_cloudwatch_event_rule" "order_email_event" {
  name           = "${var.name_prefix}-order-email-event-${var.env}"
  event_bus_name = aws_cloudwatch_event_bus.this.name

  event_pattern = jsonencode({
    source      = ["chonkychonk.orders", "chonkychonk.users"]
    detail-type = ["OrderCreated", "OrderFailure", "LowStockDetected", "UserCreated"]
  })
}

resource "aws_cloudwatch_event_target" "email_service" {
  rule           = aws_cloudwatch_event_rule.order_email_event.name
  event_bus_name = aws_cloudwatch_event_bus.this.name
  arn            = module.email_service.function_arn
}

resource "aws_lambda_permission" "eventbridge_email_service" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.email_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.order_email_event.arn
}

# ==============================================================================
# API GATEWAY (REST) — mirrors template.yaml's implicit AWS::Serverless::Api.
# ==============================================================================
resource "aws_api_gateway_rest_api" "this" {
  name = "${var.name_prefix}-api-${var.env}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.name_prefix}-api-${var.env}"
    Environment = var.env
  }
}

locals {
  top_level_resources = {
    products = "products"
    orders   = "orders"
    users    = "users"
    payments = "payments"
    webhook  = "webhook"
  }

  id_child_resources = {
    products = "productid"
    orders   = "orderId"
    users    = "userId"
  }

  lambda_functions = {
    products       = module.products
    orders         = module.orders
    users          = module.users
    payments_api   = module.payments_api
    stripe_webhook = module.stripe_webhook
  }

  api_routes = {
    products_get      = { resource_id = aws_api_gateway_resource.top["products"].id, method = "GET", fn = "products" }
    products_post     = { resource_id = aws_api_gateway_resource.top["products"].id, method = "POST", fn = "products" }
    products_id_get   = { resource_id = aws_api_gateway_resource.id["products"].id, method = "GET", fn = "products" }
    products_id_put   = { resource_id = aws_api_gateway_resource.id["products"].id, method = "PUT", fn = "products" }
    products_id_patch = { resource_id = aws_api_gateway_resource.id["products"].id, method = "PATCH", fn = "products" }
    products_id_del   = { resource_id = aws_api_gateway_resource.id["products"].id, method = "DELETE", fn = "products" }

    orders_post   = { resource_id = aws_api_gateway_resource.top["orders"].id, method = "POST", fn = "orders" }
    orders_id_get = { resource_id = aws_api_gateway_resource.id["orders"].id, method = "GET", fn = "orders" }
    orders_id_put = { resource_id = aws_api_gateway_resource.id["orders"].id, method = "PUT", fn = "orders" }
    orders_id_del = { resource_id = aws_api_gateway_resource.id["orders"].id, method = "DELETE", fn = "orders" }

    users_get    = { resource_id = aws_api_gateway_resource.top["users"].id, method = "GET", fn = "users" }
    users_post   = { resource_id = aws_api_gateway_resource.top["users"].id, method = "POST", fn = "users" }
    users_id_get = { resource_id = aws_api_gateway_resource.id["users"].id, method = "GET", fn = "users" }
    users_id_put = { resource_id = aws_api_gateway_resource.id["users"].id, method = "PUT", fn = "users" }
    users_id_del = { resource_id = aws_api_gateway_resource.id["users"].id, method = "DELETE", fn = "users" }

    payments_post = { resource_id = aws_api_gateway_resource.top["payments"].id, method = "POST", fn = "payments_api" }

    webhook_post = { resource_id = aws_api_gateway_resource.top["webhook"].id, method = "POST", fn = "stripe_webhook" }
  }

  # Every path gets a CORS preflight except /webhook — Stripe calls that
  # directly server-to-server, no browser preflight involved.
  cors_resources = merge(
    { for k, v in aws_api_gateway_resource.top : k => v.id if k != "webhook" },
    { for k, v in aws_api_gateway_resource.id : "${k}_id" => v.id }
  )
}

resource "aws_api_gateway_resource" "top" {
  for_each    = local.top_level_resources
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = each.value
}

resource "aws_api_gateway_resource" "id" {
  for_each    = local.id_child_resources
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.top[each.key].id
  path_part   = "{${each.value}}"
}

resource "aws_api_gateway_method" "route" {
  for_each      = local.api_routes
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = each.value.resource_id
  http_method   = each.value.method
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "route" {
  for_each                = local.api_routes
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.route[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.lambda_functions[each.value.fn].function_invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  for_each      = local.lambda_functions
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# ==============================================================================
# CORS PREFLIGHT (OPTIONS via MOCK integration) on every path but /webhook.
# ==============================================================================
resource "aws_api_gateway_method" "options" {
  for_each      = local.cors_resources
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "options" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration" "options" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,PATCH,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.cors_allow_origin}'"
  }
}

# ==============================================================================
# DEPLOYMENT + STAGE
# ==============================================================================
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode({
      resources    = aws_api_gateway_resource.top
      id_resources = aws_api_gateway_resource.id
      methods      = aws_api_gateway_method.route
      integrations = aws_api_gateway_integration.route
      options      = aws_api_gateway_integration.options
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.route,
    aws_api_gateway_integration.options,
    aws_api_gateway_integration_response.options,
  ]
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.env

  tags = {
    Name        = "${var.name_prefix}-api-${var.env}-stage"
    Environment = var.env
  }
}
