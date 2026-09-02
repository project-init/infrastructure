terraform {
  # optional() object attribute defaults require OpenTofu/Terraform 1.3 or newer.
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
