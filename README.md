# chonky-infra

Terraform infrastructure for the Chonky stack.

## Structure

```
chonky-infra/
├── bootstrap/                    # One-time setup: S3 state bucket, DynamoDB lock table
├── secrets/                      # Secrets Manager secrets (Stripe key/webhook, etc.)
├── deployments/
│   ├── dynamodb/                # DynamoDB tables (users/products/orders/payments/promotions)
│   │   ├── backends/
│   │   ├── dev.tfvars
│   │   └── main.tf
│   ├── cognito/                 # Cognito user pools (customers + admins)
│   │   ├── backends/
│   │   ├── dev.tfvars
│   │   └── main.tf
│   ├── custom-domain/            # API Gateway custom domain (Cloudflare + ACM)
│   ├── ses/                      # SES domain identity, DKIM, bounce/complaint tracking
│   │   ├── backends/
│   │   ├── dev.tfvars
│   │   └── main.tf
│   ├── lambdas/                   # chonky-cat-be backend: Lambdas, EventBridge, REST API
│   │   ├── backends/
│   │   ├── dev.tfvars
│   │   └── main.tf
│   └── github-oidc/               # OIDC provider + IAM role for chonky-cat-be's GitHub Actions deploy
│       ├── backends/
│       ├── dev.tfvars
│       └── main.tf
├── schema_loader/                # Legacy — RDS schema/seed data loader, unused (RDS itself has been removed)
└── modules/
    ├── s3/                       # S3 bucket module
    ├── cognito/                  # Cognito user pool + app client module
    ├── ses/                      # SES domain identity + DKIM + SNS bounce/complaint module
    └── lambda/                   # Lambda function module
```

## Deployment Order

1. **bootstrap/** — Creates S3 state bucket and DynamoDB lock table (one-time setup)
2. **secrets/** — Stores the Stripe secret key and webhook signing secret in Secrets Manager
3. **deployments/dynamodb/** — Creates the DynamoDB tables (users, products, orders, payments, promotions)
4. **deployments/cognito/** — Creates the Cognito user pools (customers, admins)
5. **deployments/ses/** — Verifies the SES sending domain (DKIM, bounce/complaint tracking via SNS)
6. **deployments/lambdas/** — Deploys the chonky-cat-be backend: Lambda functions, shared layer, EventBridge bus/rule, and REST API Gateway (depends on dynamodb + cognito + ses + secrets)
7. **deployments/github-oidc/** — Creates the OIDC provider + IAM role chonky-cat-be's GitHub Actions workflow assumes to deploy the SAM stack (independent of the steps above — no dependency on them)

`schema_loader/` is legacy — the project has migrated fully to DynamoDB and
it is not part of the deployment path above. RDS/VPC infra (`deployments/network-rds/`,
`modules/network/`, `modules/rds/`) has been removed entirely.

## Secrets Management

Sensitive values (SSH keys, database passwords, API keys) should never be committed to version control. Use environment variables instead:

### Setup

1. Set environment variables before deploying:
   ```bash
   export TF_VAR_cloudflare_api_token="cfut_MWCdTm0Mq8hWNFVSdQB4TcRXV3Q3csofrVr5uCU03cc61f43"
   export TF_VAR_cloudflare_zone_id="67895aca788aaa1d6cb4bc58312cc096"
   export TF_VAR_stripe_secret_key="sk_test_51Tj1XXPQ8KoWpSNkdJA9BqKdG3tlZ00HcXwZ6b3nJWHkCicpoogRI1LQZSt2G1w24EnShEe9cF7LdxyqvgR0mjt9009CmDz22W"
   export TF_VAR_stripe_publish_key="pk_test_51Tj1XXPQ8KoWpSNku6YwI3YpxH6VRwJE1IZYDQyPA6b4o7G5i5JcdjN2P5wcKgz8OqdEC04GEUXLlkSBSXww1XRa0071XBFN56"
   ```

2. Create the Stripe webhook endpoint and pick up its signing secret (no manual dashboard copy-paste):
   ```bash
   cd secrets
   eval "$(./create-stripe-webhook.sh)"   # sets TF_VAR_stripe_webhook_secret
   ```
   Re-running this is safe (it detects the existing endpoint and refuses to touch it); pass
   `--recreate` if you need a fresh secret, which immediately invalidates the old one.

3. Deploy secrets:
   ```bash
   terraform apply -var-file="dev.tfvars"
   ```

### Or use a deployment script

Create `secrets/deploy.sh` (git-ignored):
```bash
#!/bin/bash
export TF_VAR_stripe_secret_key="your-stripe-key"
eval "$(./create-stripe-webhook.sh)"
terraform apply -var-file="dev.tfvars"
```

Then:
```bash
chmod +x secrets/deploy.sh
./secrets/deploy.sh
```

### Why environment variables?

- ✅ SSH keys and passwords never in files or version control
- ✅ Standard practice for secrets in CI/CD pipelines
- ✅ Works seamlessly with Terraform and shell automation
- ✅ No local tfvars files to accidentally commit

### For production

Use AWS Secrets Manager, HashiCorp Vault, or your organization's secret management service.

## Quick Start

```bash
# 1. Bootstrap (one-time)
cd bootstrap
terraform init
terraform apply

# 2. Secrets (set environment variables first)
export TF_VAR_stripe_secret_key="sk_test_51Tj1XXPQ8KoWpSNkdJA9BqKdG3tlZ00HcXwZ6b3nJWHkCicpoogRI1LQZSt2G1w24EnShEe9cF7LdxyqvgR0mjt9009CmDz22W"
export TF_VAR_stripe_webhook_secret="whsec_..."
export TF_VAR_cloudflare_api_token="cfut_MWCdTm0Mq8hWNFVSdQB4TcRXV3Q3csofrVr5uCU03cc61f43"
export TF_VAR_cloudflare_zone_id="67895aca788aaa1d6cb4bc58312cc096"

cd secrets
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"

# 3. DynamoDB tables
cd ../deployments/dynamodb
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"

# 4. Cognito user pools
cd ../cognito
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"

# 5. SES domain identity (DKIM, bounce/complaint tracking)
cd ../ses
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"

# 6. Backend Lambda functions (chonky-cat-be), EventBridge, REST API
cd ../lambdas
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"
```
