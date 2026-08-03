resource "aws_s3_bucket" "this" {
  bucket        = "${var.name_prefix}-${var.bucket_suffix}-${var.env}"
  force_destroy = var.force_destroy

  tags = {
    Name        = "${var.name_prefix}-${var.bucket_suffix}-${var.env}"
    Environment = var.env
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# AWS-managed SSE-S3 accepted here — no ongoing KMS cost/rotation for
# buckets this module provisions (product images, etc.).
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}