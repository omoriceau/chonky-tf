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
# USERS
# Simple key-value table. Looked up by id (PK) or by email (GSI) for
# login/signup checks.
# ==============================================================================
resource "aws_dynamodb_table" "users" {
  name         = "${var.name_prefix}-users-${var.env}"
  billing_mode = var.billing_mode
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = {
    Name        = "${var.name_prefix}-users-${var.env}"
    Environment = var.env
  }
}

# ==============================================================================
# PRODUCTS
# CategoryIndex covers "browse by category" pagination.
# ReorderIndex is a SPARSE index: the `reorder_flag` attribute is only written
# onto an item when qty <= low_stock_threshold, and removed once restocked.
# This keeps the low-stock reorder report querying a tiny index instead of
# scanning the whole catalog.
# ==============================================================================
resource "aws_dynamodb_table" "products" {
  name         = "${var.name_prefix}-products-${var.env}"
  billing_mode = var.billing_mode
  hash_key     = "product_id"

  attribute {
    name = "product_id"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  attribute {
    name = "name"
    type = "S"
  }

  # Sparse GSI key — only present on items that currently need reordering.
  attribute {
    name = "reorder_flag"
    type = "S"
  }

  global_secondary_index {
    name            = "CategoryIndex"
    hash_key        = "category"
    range_key       = "name"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "ReorderIndex"
    hash_key        = "reorder_flag"
    range_key       = "product_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = {
    Name        = "${var.name_prefix}-products-${var.env}"
    Environment = var.env
  }
}

# ==============================================================================
# ORDERS
# Single-table layout per order: the main order record plus its order_items
# and order_tracking children all share the same partition key (order_id) so
# a single Query returns the full order.
#   SK = "ORDER"            -> main order record (also carries applied_promotions)
#   SK = "ITEM#<n>"         -> order_items children
#   SK = "TRACKING#<ts>"    -> order_tracking children
#
# UserOrdersIndex and StatusIndex are SPARSE: user_id/status attributes only
# exist on the "ORDER" sort-key item, so children never show up in either index.
# ==============================================================================
resource "aws_dynamodb_table" "orders" {
  name         = "${var.name_prefix}-orders-${var.env}"
  billing_mode = var.billing_mode
  hash_key     = "order_id"
  range_key    = "sk"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "UserOrdersIndex"
    hash_key        = "user_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = {
    Name        = "${var.name_prefix}-orders-${var.env}"
    Environment = var.env
  }
}

# ==============================================================================
# PAYMENTS
# Partitioned by order_id so a Query returns every payment attempt and refund
# for that order in one call.
#   SK = "PAYMENT#<payment_id>" -> main payment record
#   SK = "REFUND#<refund_id>"   -> refund children
#
# ProviderTxnIndex is SPARSE: only payment records carry
# provider_transaction_id, and only once the provider has returned one — used
# by the (future) Stripe webhook handler to find a payment by transaction id.
# ==============================================================================
resource "aws_dynamodb_table" "payments" {
  name         = "${var.name_prefix}-payments-${var.env}"
  billing_mode = var.billing_mode
  hash_key     = "order_id"
  range_key    = "sk"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  attribute {
    name = "provider_transaction_id"
    type = "S"
  }

  global_secondary_index {
    name            = "ProviderTxnIndex"
    hash_key        = "provider_transaction_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = {
    Name        = "${var.name_prefix}-payments-${var.env}"
    Environment = var.env
  }
}

# ==============================================================================
# PROMOTIONS
# Small, standalone table. Always looked up by its natural key — the code
# itself (e.g. "SAVE10") — so that's the partition key directly.
# Which promotions applied to which order lives as an `applied_promotions`
# list attribute on the order's "ORDER" item, not here.
# ==============================================================================
resource "aws_dynamodb_table" "promotions" {
  name         = "${var.name_prefix}-promotions-${var.env}"
  billing_mode = var.billing_mode
  hash_key     = "code"

  attribute {
    name = "code"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = {
    Name        = "${var.name_prefix}-promotions-${var.env}"
    Environment = var.env
  }
}
