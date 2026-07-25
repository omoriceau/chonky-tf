# chonky-infra

Terraform infrastructure for the Chonky stack.

## Structure

```
chonky-infra/
├── bootstrap/                    # One-time setup: S3 state bucket, DynamoDB lock table
├── secrets/                      # Secrets Manager secrets (Stripe key, etc.)
├── deployments/
│   ├── dynamodb/                # DynamoDB tables (users/products/orders/payments/promotions)
│   ├── cognito/                 # Cognito user pools (customers + admins)
│   ├── admin-hosting/           # Admin SPA hosting (S3 + CloudFront, Cloudflare DNS)
│   ├── ses/                     # SES domain identity, DKIM, bounce/complaint tracking
│   └── lambdas/                 # chonky-cat-be backend: Lambdas, EventBridge, REST API
│       ├── backends/
│       ├── dev.tfvars
│       └── main.tf
├── dynamodb_loader/              # Seeds the DynamoDB tables with dev/test data
├── dev_image_loader/             # Seeds an S3 bucket with placeholder product images
└── modules/
    ├── s3/                       # S3 bucket module
    ├── cognito/                  # Cognito user pool + app client module
    ├── ses/                      # SES domain identity + DKIM + SNS bounce/complaint module
    ├── spa-hosting/              # S3 + CloudFront SPA hosting module
    └── lambda/                   # Lambda function module
```

Each `deployments/*` directory follows the same shape (`backends/`, `dev.tfvars`, `main.tf`) even where not shown above.

## Deployment Order

1. **bootstrap/** — Creates S3 state bucket and DynamoDB lock table (one-time setup)
2. **secrets/** — Stores the Stripe secret key in Secrets Manager
3. **deployments/dynamodb/** — Creates the DynamoDB tables (users, products, orders, payments, promotions)
4. **deployments/cognito/** — Creates the Cognito user pools (customers, admins)
5. **deployments/ses/** — Verifies the SES sending domain (DKIM, bounce/complaint tracking via SNS)
6. **deployments/lambdas/** — Deploys the chonky-cat-be backend: Lambda functions, shared layer, EventBridge bus/rule, and REST API Gateway (depends on dynamodb + secrets)
7. **dynamodb_loader/** — Seeds the DynamoDB tables with dev/test data (optional, dev convenience)
8. **dev_image_loader/** — Seeds a public S3 bucket with placeholder product images (optional, dev convenience)

## Secrets Management

Sensitive values (API keys, etc.) should never be committed to version control. Use environment variables instead:

### Setup

1. Set environment variables before deploying:
   ```bash
   export TF_VAR_stripe_secret_key="your-stripe-key"
   ```

2. Deploy secrets:
   ```bash
   cd secrets
   terraform apply -var-file="dev.tfvars"
   ```

### Or use a deployment script

Create `secrets/deploy.sh` (git-ignored):
```bash
#!/bin/bash
export TF_VAR_stripe_secret_key="your-stripe-key"
terraform apply -var-file="dev.tfvars"
```

Then:
```bash
chmod +x secrets/deploy.sh
./secrets/deploy.sh
```

### Why environment variables?

- ✅ Secrets never in files or version control
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
export TF_VAR_stripe_secret_key="your-stripe-key"

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
