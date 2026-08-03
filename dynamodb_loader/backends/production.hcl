bucket         = "chonky-tfstate-production"
key            = "env/production/schema-loader/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-production" 