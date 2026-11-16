# Week 08, Lab 8.1: Week 5's VPC, reproduced in Terraform.
# Same as the handbook's main.tf, plus pinned provider version, default tags, and outputs.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "intern01" # SSO profile (account 604531678534); run `aws sso login --profile intern01` first

  # Every resource Terraform creates gets these tags, so it's obvious in the console
  # which resources are Terraform-managed (and must not be edited by hand).
  default_tags {
    tags = {
      Project   = "week-08"
      ManagedBy = "terraform"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "training-vpc-tf"
  cidr = "10.1.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnets = ["10.1.101.0/24", "10.1.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true # one NAT (~$0.045/hr) instead of one per AZ, like Week 5
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "nat_public_ips" {
  value = module.vpc.nat_public_ips
}
