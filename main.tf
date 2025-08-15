provider "aws" {
  region = var.region
  #   assume_role {
  #     role_arn = "arn:aws:iam::${var.aws_account_id}:role/terraformAdmin"
  #   }
}

terraform {
  backend "s3" {
    bucket       = "tf-state-homework"
    key          = "backend/terraform.tfstate"
    encrypt      = true
    profile      = "default"
    region       = "eu-central-1"
    use_lockfile = true
  }
}