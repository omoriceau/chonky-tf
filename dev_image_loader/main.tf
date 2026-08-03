terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
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

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# prod gets the bare domain; every other env gets an <env>- prefix, same
# convention as deployments/lambdas' api_domain_name.
locals {
  img_domain_name = var.env == "prod" ? "img.chonkycat.ca" : "${var.env}-img.chonkycat.ca"
}

# CloudFront requires the certificate in us-east-1 regardless of the
# distribution's own region — var.region already defaults to us-east-1,
# matching every other deployment in this repo, so no provider alias
# is needed here (same reasoning as deployments/admin-hosting).
resource "aws_acm_certificate" "img" {
  domain_name       = local.img_domain_name
  validation_method = "DNS"

  tags = {
    Name        = "${var.name_prefix}-img-cert-${var.env}"
    Environment = var.env
  }

  lifecycle {
    create_before_destroy = true
  }
}

# proxied = false is required: ACM validation CNAMEs must resolve directly
# (DNS-only), not through Cloudflare's proxy, or validation will fail.
resource "cloudflare_record" "img_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.img.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.value
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "img" {
  certificate_arn         = aws_acm_certificate.img.arn
  validation_record_fqdns = [for record in cloudflare_record.img_cert_validation : record.hostname]
}

# ==============================================================================
# BUCKET — private, no public access. Every read goes through CloudFront via
# the Origin Access Control below, matching modules/spa-hosting and
# chonky-cat-fe's own config.js comment ("img.chonkycat.ca -> Cloudflare ->
# CloudFront (OAC) -> private S3 bucket"). Anonymous storefront visitors
# still load these with a plain <img src> — OAC just means only CloudFront
# can read the bucket directly, not the public.
# ==============================================================================
module "images_bucket" {
  source = "../modules/s3"

  name_prefix   = var.name_prefix
  bucket_suffix = "images"
  env           = var.env

  force_destroy = true
}

resource "aws_cloudfront_origin_access_control" "img" {
  name                              = "${module.images_bucket.bucket_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "img" {
  enabled     = true
  aliases     = [local.img_domain_name]
  price_class = "PriceClass_100"
  comment     = "${var.name_prefix}-img-${var.env}"

  origin {
    domain_name              = module.images_bucket.bucket_regional_domain_name
    origin_id                = module.images_bucket.bucket_name
    origin_access_control_id = aws_cloudfront_origin_access_control.img.id
  }

  default_cache_behavior {
    target_origin_id       = module.images_bucket.bucket_name
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS-managed CachingOptimized
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.img.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.name_prefix}-img-${var.env}"
    Environment = var.env
  }
}

# Scoped to img/* and to exactly this distribution's OAC, mirroring
# modules/spa-hosting's bucket policy.
resource "aws_s3_bucket_policy" "img_oac" {
  bucket = module.images_bucket.bucket_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${module.images_bucket.bucket_arn}/img/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.img.arn
        }
      }
    }]
  })
}

# Points the domain at CloudFront. proxied = false — CloudFront already
# terminates TLS and serves as the CDN; routing it through Cloudflare's
# proxy too would add a second CDN layer and break the ACM cert's hostname
# match (same reasoning as deployments/admin-hosting).
resource "cloudflare_record" "img_site" {
  zone_id = var.cloudflare_zone_id
  name    = local.img_domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.img.domain_name
  ttl     = 300
  proxied = false
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

  depends_on = [aws_s3_bucket_policy.img_oac]
}
