# deployments/dynamodb/backends/dev.hcl
bucket         = "chonky-tfstate-dev"
key            = "env/dev/dynamodb/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-dev"
