bucket         = "chonky-tfstate-production"
key            = "env/production/secrets/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-production"