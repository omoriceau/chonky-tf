# deployments/ses/backends/production.hcl
bucket         = "chonky-tfstate-production"
key            = "env/production/ses/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-production"
