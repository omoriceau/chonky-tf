# chonky-infra

Terraform infrastructure for the Chonky stack.

## Structure

```
chonky-infra/
├── bootstrap/                    # One-time setup: S3 state bucket, DynamoDB lock table
├── secrets/                      # Secrets Manager secrets (RDS password, etc.)
├── deployments/
│   ├── network-rds/             # VPC, subnets, RDS (depends on secrets)
│   │   ├── backends/
│   │   ├── dev.tfvars
│   │   └── main.tf
│   └── lambdas/                 # Lambda functions (separate state)
│       ├── backends/
│       ├── dev.tfvars
│       └── main.tf
├── schema_loader/               # Database schema and seed data
└── modules/
    ├── network/                 # VPC + subnets
    ├── rds/                     # RDS instance
    └── lambda/                  # Lambda function module
```

## Deployment Order

1. **bootstrap/** — Creates S3 state bucket and DynamoDB lock table (one-time setup)
2. **secrets/** — Stores RDS password in Secrets Manager (required before network-rds)
3. **deployments/network-rds/** — Creates VPC, subnets, and RDS instance
4. **schema_loader/** — Loads database schema and seed data
5. **deployments/lambdas/** — Creates Lambda functions

## Secrets Management

Sensitive values (SSH keys, database passwords, API keys) should never be committed to version control. Use environment variables instead:

### Setup

1. Set environment variables before deploying:
   ```bash
   export TF_VAR_ssh_private_key="$(cat chonky.pem)"
   export TF_VAR_db_pass="your-secure-password"
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
export TF_VAR_ssh_private_key="$(cat ../chonky.pem)"
export TF_VAR_db_pass="your-secure-password"
export TF_VAR_stripe_secret_key="your-stripe-key"
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
export TF_VAR_ssh_private_key="$(cat chonky.pem)"
export TF_VAR_db_pass="your-secure-password"
export TF_VAR_stripe_secret_key="your-stripe-key"

cd secrets
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"

# 3. Network and RDS
cd ../deployments/network-rds
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"

# 4. Database schema
cd ../../schema_loader
terraform init
terraform apply -var-file="dev.tfvars"

# 5. Lambda functions
cd ../deployments/lambdas
terraform init -backend-config=backends/dev.hcl
terraform apply -var-file="dev.tfvars"
```
