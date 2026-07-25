terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

# ==============================================================================
# BUCKET — plain public-read bucket (scoped to img/* only) via a bucket
# policy, not Cognito-signed access, since anonymous storefront visitors
# need to load these with a plain <img src>. Mirrors chonky-cat-fe's
# scripts/push-images.mjs, which provisioned this by hand before this
# deployment existed.
# ==============================================================================
module "images_bucket" {
  source = "../modules/s3"

  name_prefix   = var.name_prefix
  bucket_suffix = "images"
  env           = var.env

  block_public_policy     = false
  restrict_public_buckets = false
  force_destroy           = true
}

resource "aws_s3_bucket_policy" "public_read_images" {
  bucket = module.images_bucket.bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadProductImages"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${module.images_bucket.bucket_arn}/img/*"
    }]
  })

  # Must wait for the module's public_access_block to actually disable
  # BlockPublicPolicy first, or PutBucketPolicy 403s — bucket_name alone
  # isn't a strong enough implicit dependency since that resource creates
  # in parallel with the policy otherwise.
  depends_on = [module.images_bucket]
}

# ==============================================================================
# LOAD — no VPC/EC2/SSH needed, same as dynamodb_loader: S3 is a public AWS
# API endpoint, so local-exec can reach it directly from wherever
# `terraform apply` runs.
#
# Triggers re-run the load whenever the script, base images, or seed data
# change. Safe to re-run any time — SKUs derive a deterministic key
# (img/<sku>.jpg), so re-running overwrites the same objects in place.
# ==============================================================================
resource "null_resource" "load_images" {
  triggers = {
    script_hash      = filesha256("${path.module}/load_images.py")
    seed_data_hash   = filesha256(var.seed_data_path)
    dry_image_hash   = filesha256("${path.module}/${var.base_imgs_dir}/dry.jpg")
    wet_image_hash   = filesha256("${path.module}/${var.base_imgs_dir}/wet.jpg")
    treat_image_hash = filesha256("${path.module}/${var.base_imgs_dir}/treat.jpg")
    bucket           = module.images_bucket.bucket_name
  }

  provisioner "local-exec" {
    command     = "pip install -r requirements.txt --quiet --break-system-packages && python3 load_images.py"
    working_dir = path.module

    environment = {
      IMAGES_BUCKET  = module.images_bucket.bucket_name
      SEED_DATA_PATH = var.seed_data_path
      BASE_IMGS_DIR  = var.base_imgs_dir
      AWS_REGION     = var.region
    }
  }

  depends_on = [aws_s3_bucket_policy.public_read_images]
}
