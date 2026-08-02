provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "springboot-devsecops"
      Environment = "dev"
      ManagedBy   = "Terraform"
      Owner       = "Mina"
    }
  }
}
