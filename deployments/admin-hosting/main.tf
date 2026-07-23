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
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# CloudFront requires the certificate in us-east-1 regardless of the
# distribution's own region — var.region already defaults to us-east-1,
# matching every other deployment in this repo, so no provider alias
# is needed here.
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name        = "${var.name_prefix}-admin-cert-${var.env}"
    Environment = var.env
  }

  lifecycle {
    create_before_destroy = true
  }
}

# proxied = false is required: ACM validation CNAMEs must resolve directly
# (DNS-only), not through Cloudflare's proxy, or validation will fail.
resource "cloudflare_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in cloudflare_record.cert_validation : record.hostname]
}

module "hosting" {
  source = "../../modules/spa-hosting"

  name_prefix         = var.name_prefix
  env                 = var.env
  domain_name         = var.domain_name
  acm_certificate_arn = aws_acm_certificate_validation.this.certificate_arn
}

# Points the domain at CloudFront. proxied = false — CloudFront already
# terminates TLS and serves as the CDN; routing it through Cloudflare's
# proxy too would add a second CDN layer and break the ACM cert's hostname
# match (matches the guidance in scripts/setup-hosting.sh).
resource "cloudflare_record" "site" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  type    = "CNAME"
  content = module.hosting.distribution_domain_name
  ttl     = 300
  proxied = false
}
