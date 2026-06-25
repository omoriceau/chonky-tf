bucket         = "chonky-tfstate-dev"
key            = "env/dev/schema-loader/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-dev"
key_name       = "chonky"