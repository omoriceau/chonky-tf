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

# Only ever exercised when custom_domain_enabled is true (see below) — an
# empty token here never causes a plan/apply failure on its own, since no
# resource calls the Cloudflare API unless that's true.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ==============================================================================
# REMOTE STATE — pulls the real Cognito pool/client ids so deploy-products.sh
# isn't relying on its own hardcoded defaults (which go stale if the pools
# are ever torn down and recreated — see the script's own comment on
# ADMIN_COGNITO_USER_POOL_ID/CUSTOMER_COGNITO_USER_POOL_ID).
# ==============================================================================
data "terraform_remote_state" "cognito" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/cognito/terraform.tfstate"
    region = var.region
  }
}

locals {
  checkout_dir = coalesce(var.checkout_dir != "" ? var.checkout_dir : null, "${path.module}/.be-checkout")

  # deploy-products.sh itself verifies the DynamoDB tables exist and creates
  # the S3 SAM-artifacts bucket / EventBridge bus if missing — this module
  # doesn't duplicate any of that, just pulls chonky-cat-be's master branch
  # and hands off to the script with real, non-stale parameters.
  deploy_args = concat(
    [
      "--environment", var.env,
      "--region", var.region,
      "--dev-email", var.dev_email,
      "--admin-cognito-pool-id", data.terraform_remote_state.cognito.outputs.admins_user_pool_id,
      "--customer-cognito-pool-id", data.terraform_remote_state.cognito.outputs.customers_user_pool_id,
      "--customer-cognito-client-id", data.terraform_remote_state.cognito.outputs.customers_app_client_id,
    ],
    var.ses_domain != "" ? ["--ses-domain", var.ses_domain] : []
  )

  # chonky-cat-be's .gitignore has a too-broad `python/` pattern that also
  # matches shared/python/ — the directory template.yaml's SharedLayer
  # packages (ContentUri: shared/python/). It's manually-maintained source
  # (a python/shared/ copy of shared/*.py, laid out that way so Lambda's
  # layer path convention makes `from shared.db import ...` work), not a
  # build artifact, so a fresh clone is always missing it and `sam build`
  # fails packaging SharedLayer. Reconstructed here before every deploy
  # rather than fixed upstream, since this module shouldn't silently rewrite
  # chonky-cat-be's own .gitignore/repo layout — flag it there instead.
  rebuild_shared_layer = "mkdir -p shared/python/shared && cp shared/*.py shared/python/shared/"

  # This module re-invokes deploy-products.sh on every terraform apply (that's
  # what "pull and deploy" means — always converge to whatever's on master).
  # But `sam deploy` treats "no changes to deploy" as a hard error, and this
  # script has `set -euo pipefail`, so any apply that lands after master
  # hasn't moved would otherwise fail outright even though nothing is
  # actually wrong. Caught here rather than patched into the script, for the
  # same reason as rebuild_shared_layer above — not this module's repo to
  # edit. Any other failure still propagates (real exit status, full output).
  deploy_command = <<-EOT
    set -euo pipefail
    ${local.rebuild_shared_layer}

    set +e
    DEPLOY_OUTPUT=$(./deploy-products.sh ${join(" ", [for a in local.deploy_args : "\"${a}\""])} 2>&1)
    DEPLOY_STATUS=$?
    set -e

    echo "$DEPLOY_OUTPUT"

    if [ "$DEPLOY_STATUS" -ne 0 ]; then
      if echo "$DEPLOY_OUTPUT" | grep -q "No changes to deploy"; then
        echo "[INFO] Stack already up to date (no changes) — treating as success."
      else
        exit "$DEPLOY_STATUS"
      fi
    fi
  EOT

  # production gets the bare domain; every other env gets an <env>- prefix so
  # dev/staging can run side by side without fighting over the same hostname.
  api_domain_name = var.api_domain_name != "" ? var.api_domain_name : (
    var.env == "production" ? "api.chonkycat.ca" : "${var.env}-api.chonkycat.ca"
  )

  # Custom domain setup needs to create a Cloudflare DNS record (for ACM's
  # DNS validation, and for the domain itself) — skip the whole thing rather
  # than fail the apply when those creds aren't supplied.
  #
  # nonsensitive(): custom_domain_enabled is just a bool (reveals nothing
  # about the token itself) but for_each below rejects any value derived
  # from a sensitive input, sensitive or not, unless unwrapped explicitly.
  custom_domain_enabled = nonsensitive(var.cloudflare_api_token != "") && var.cloudflare_zone_id != ""
}

module "chonkycat_be" {
  source = "../../modules/git_deploy"

  repo_url     = var.repo_url
  branch       = var.branch
  checkout_dir = local.checkout_dir

  deploy_command = local.deploy_command
  force_redeploy = var.force_redeploy

  env_vars = {
    AWS_REGION = var.region
  }
}

# ==============================================================================
# Surfaces the live stack's outputs (API endpoints, function ARNs, event bus)
# once deploy-products.sh's `sam deploy` has run. The SAM/CloudFormation
# stack is the actual source of truth for these — this module only shells
# out to the script, it doesn't declare any of the underlying resources.
# ==============================================================================
data "aws_cloudformation_stack" "chonkychonk_products" {
  name       = "chonkychonk-products-${var.env}"
  depends_on = [module.chonkycat_be]
}

# ==============================================================================
# Custom domain — <env>-api.chonkycat.ca (bare api.chonkycat.ca for production),
# pointed at this stack's API Gateway.
#
# deploy-products.sh's own attach_custom_domain() only maps a base path onto
# a domain that ALREADY exists in API Gateway — it can't provision the ACM
# cert or the domain itself (confirmed: it printed "Custom domain
# 'api.chonkycat.ca' not found in API Gateway — skipping mapping" on the
# first real deploy through this module). So that part is done here instead,
# same ACM-cert + Cloudflare-DNS-validation pattern as deployments/
# admin-hosting, then a base path mapping onto ChonkyRestApi's "" (root).
#
# The API is EDGE-optimized (SAM's default for an implicit
# AWS::Serverless::Api, confirmed via `aws apigateway get-rest-api`) so the
# cert has to live in us-east-1 regardless of var.region, same reasoning as
# admin-hosting's CloudFront cert.
#
# Entirely skipped — see custom_domain_enabled above — when Cloudflare
# creds aren't supplied; api_custom_domain_status in outputs.tf explains why
# when that happens, instead of the apply just failing.
# ==============================================================================
resource "aws_acm_certificate" "api" {
  count = local.custom_domain_enabled ? 1 : 0

  domain_name       = local.api_domain_name
  validation_method = "DNS"

  tags = {
    Name        = "chonkychonk-api-${var.env}"
    Environment = var.env
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "api_cert_validation" {
  for_each = local.custom_domain_enabled ? {
    for dvo in aws_acm_certificate.api[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  } : {}

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.value
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "api" {
  count = local.custom_domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [for record in cloudflare_record.api_cert_validation : record.hostname]
}

resource "aws_api_gateway_domain_name" "api" {
  count = local.custom_domain_enabled ? 1 : 0

  domain_name     = local.api_domain_name
  certificate_arn = aws_acm_certificate_validation.api[0].certificate_arn

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "cloudflare_record" "api" {
  count = local.custom_domain_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.api_domain_name
  type    = "CNAME"
  content = aws_api_gateway_domain_name.api[0].cloudfront_domain_name
  ttl     = 300
  proxied = false
}

# The implicit REST API's physical id. There's no aws_cloudformation_stack_
# resource data source in this provider version to look it up directly (the
# way deploy-products.sh's own attach_custom_domain() does via `aws
# cloudformation describe-stack-resources --logical-resource-id
# ServerlessRestApi`) — pulled instead from the ProductsApi output's host,
# https://<rest_api_id>.execute-api.<region>.amazonaws.com/<env>/products.
locals {
  rest_api_id = local.custom_domain_enabled ? split(
    ".", replace(data.aws_cloudformation_stack.chonkychonk_products.outputs["ProductsApi"], "https://", "")
  )[0] : null
}

resource "aws_api_gateway_base_path_mapping" "api" {
  count = local.custom_domain_enabled ? 1 : 0

  api_id      = local.rest_api_id
  stage_name  = var.env
  domain_name = aws_api_gateway_domain_name.api[0].domain_name
  base_path   = ""
}
