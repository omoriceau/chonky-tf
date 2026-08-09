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
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
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

# Looks up whether an OAC named "<domain_name>-oac" already exists directly
# in AWS. Guards against exactly what happened on 2026-08-05: the OAC (and
# chonky-images-dev-oac before it, 2026-08-03) survived in the account while
# this stack's state didn't know about it — most likely backend/state churn
# during the chonky-tfstate bucket rename — so a plain `resource` block
# collided with a 409 OriginAccessControlAlreadyExists instead of adopting
# it. CloudTrail shows zero DeleteOriginAccessControl calls ever, confirming
# these were orphaned from state, not actually destroyed.
data "external" "existing_oac" {
  program = ["bash", "-c", <<-EOT
    ID=$(aws cloudfront list-origin-access-controls \
      --query "OriginAccessControlList.Items[?Name=='${var.domain_name}-oac'].Id | [0]" \
      --output text 2>/dev/null)
    [ "$ID" = "None" ] && ID=""
    printf '{"id":"%s"}' "$ID"
  EOT
  ]
}

# Import blocks are only valid in the root module (can't live inside
# modules/spa-hosting itself). A no-op once the resource is already tracked
# in state — safe to leave here permanently rather than as a one-time fix.
import {
  for_each = data.external.existing_oac.result.id != "" ? { existing = data.external.existing_oac.result.id } : {}
  to       = module.hosting.aws_cloudfront_origin_access_control.this
  id       = each.value
}

data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# Assumed by .github/workflows/deploy.yml in chonkycat-admin (via
# aws-actions/configure-aws-credentials OIDC) — trust is scoped to that
# repo's master branch only, matching the workflow's `on: push: branches:
# [master]` trigger.
resource "aws_iam_role" "github_actions_deploy" {
  name = "${var.name_prefix}-admin-github-actions-deploy-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:omoriceau/chonkycat-admin:ref:refs/heads/master"
        }
      }
    }]
  })

  tags = {
    Name        = "${var.name_prefix}-admin-github-actions-deploy-${var.env}"
    Environment = var.env
  }
}

# Scoped to exactly this bucket and this distribution — no broader S3/
# CloudFront access, unlike chonky-cat-be-github-actions-deploy's use of
# AWS-managed full-access policies.
resource "aws_iam_role_policy" "github_actions_deploy_scoped" {
  name = "admin-deploy-scoped"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SyncBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          module.hosting.bucket_arn,
          "${module.hosting.bucket_arn}/*",
        ]
      },
      {
        Sid      = "InvalidateCloudFront"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = module.hosting.distribution_arn
      },
    ]
  })
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
