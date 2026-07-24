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

# Read rather than hardcoded, since the CloudFront distribution ID isn't
# known ahead of that deployment actually creating it. Means admin-hosting
# must be applied (at least once) before this stack's admin role resources.
data "terraform_remote_state" "admin_hosting" {
  backend = "s3"
  config = {
    bucket = "chonky-tfstate-${var.env}"
    key    = "env/${var.env}/admin-hosting/terraform.tfstate"
    region = var.region
  }
}

# ==============================================================================
# OIDC provider — lets GitHub Actions assume an AWS role via short-lived
# tokens instead of long-lived access keys. One provider per account; any
# future workflow in any repo can reuse it by adding its own role.
# ==============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer actually validates this value against the live cert
  # chain, but the provider resource still requires one of the right
  # shape. Fetched directly from token.actions.githubusercontent.com's
  # served chain (its top intermediate, ISRG Root YR, issued by ISRG Root
  # X1 — GitHub serves via Let's Encrypt, not the DigiCert chain older
  # guides reference):
  #   openssl s_client -connect token.actions.githubusercontent.com:443 -showcerts
  thumbprint_list = [
    "ab9d0263244dd0326eb67015705a667e79cfe998",
  ]
}

# ==============================================================================
# Role assumed by chonky-cat-be's deploy-dev GitHub Actions job.
#
# Trust is scoped via the OIDC `sub` claim to pushes on main only — the
# PR-validation job (sam build/validate) never calls
# configure-aws-credentials, so it doesn't need this role at all.
# ==============================================================================
resource "aws_iam_role" "github_actions_deploy" {
  name = "chonky-cat-be-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# Deploy permissions — covers everything deploy-products.sh + `sam deploy`
# touch for the chonkychonk-products-dev stack: CloudFormation stack
# lifecycle, Lambda + layers, API Gateway, IAM (CAPABILITY_IAM — SAM
# creates/updates Lambda execution roles), EventBridge, the SAM artifacts
# bucket, and DynamoDB DescribeTable (the script only verifies tables
# exist, never writes them). Expect to add permissions here if the first
# real run throws AccessDenied — normal for a first SAM CI setup.
# ==============================================================================
resource "aws_iam_role_policy_attachment" "cloudformation" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudFormationFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
}

resource "aws_iam_role_policy_attachment" "apigateway" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator"
}

resource "aws_iam_role_policy_attachment" "eventbridge" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}

resource "aws_iam_role_policy" "deploy_scoped" {
  name = "chonky-cat-be-deploy-scoped"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PassAndManageLambdaExecutionRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/chonkychonk-*"
      },
      {
        Sid    = "SamArtifactsBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:CreateBucket",
          "s3:HeadBucket",
          "s3:PutBucketPolicy",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketVersioning",
        ]
        Resource = [
          "arn:aws:s3:::chonkychonk-sam-artifacts-*",
          "arn:aws:s3:::chonkychonk-sam-artifacts-*/*",
        ]
      },
      {
        Sid      = "DynamoDbTableCheck"
        Effect   = "Allow"
        Action   = ["dynamodb:DescribeTable"]
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/chonky-*"
      },
      {
        Sid    = "LambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups",
          "logs:TagResource",
        ]
        Resource = "*"
      },
    ]
  })
}

# ==============================================================================
# Role assumed by chonkychonk-admin's deploy GitHub Actions job.
#
# Trust is scoped via the OIDC `sub` claim to pushes on master only — this
# repo's default/only branch is `master`, unlike chonky-cat-be's `main`.
# ==============================================================================
resource "aws_iam_role" "github_actions_deploy_admin" {
  name = "chonky-cat-admin-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.chonkycat_admin_repo}:ref:refs/heads/master"
          }
        }
      }
    ]
  })
}

# Scoped to exactly the bucket + distribution deployments/admin-hosting
# created (via remote state) — covers what scripts/deploy.sh does: sync the
# built dist/ to the bucket, then invalidate the CloudFront cache.
resource "aws_iam_role_policy" "admin_deploy_scoped" {
  name = "chonky-cat-admin-deploy-scoped"
  role = aws_iam_role.github_actions_deploy_admin.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SyncBuiltAssetsToBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          data.terraform_remote_state.admin_hosting.outputs.bucket_arn,
          "${data.terraform_remote_state.admin_hosting.outputs.bucket_arn}/*",
        ]
      },
      {
        Sid      = "InvalidateCache"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = data.terraform_remote_state.admin_hosting.outputs.distribution_arn
      },
    ]
  })
}
