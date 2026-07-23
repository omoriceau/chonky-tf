# deployments/github-oidc/backends/dev.hcl
bucket         = "chonky-tfstate-dev"
key            = "env/dev/github-oidc/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-dev"
