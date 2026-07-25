bucket         = "chonky-tfstate-dev"
key            = "env/dev/dev_image_loader/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chonky-tfstate-lock-dev"
