bucket         = "chonky-tfstate-prod"
key            = "env/prod/schema-loader/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-prod" 