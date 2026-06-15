# chonky-infra

Terraform infrastructure for the Chonky stack.

## Structure

```
chonky-infra/
├── bootstrap/
│   └── dev/          # One-time setup: S3 state bucket + DynamoDB lock table
├── env/
│   └── dev/          # Dev environment — wires up all modules
└── modules/
    ├── network/      # VPC + subnets
    └── rds/          # Security group, subnet group, RDS instance
```

## First-time setup (bootstrap)

Run bootstrap once per environment to create the S3 bucket and DynamoDB lock table
before any other Terraform can run.

```bash
cd bootstrap/dev
terraform init
terraform apply
```

## Deploying an environment

```bash
cd env/dev
terraform init
export TF_VAR_db_pass="your-secure-password"
terraform plan
terraform apply
```

## Adding a new environment

1. Copy `bootstrap/dev` → `bootstrap/<env>` and update the bucket/table names.
2. Copy `env/dev` → `env/<env>` and update the backend config and defaults.
3. Run bootstrap, then deploy.
```
