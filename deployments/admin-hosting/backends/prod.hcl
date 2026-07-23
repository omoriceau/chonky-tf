# deployments/admin-hosting/backends/prod.hcl
bucket         = "chonky-tfstate-prod"
key            = "env/prod/admin-hosting/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-prod"
