terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Same state bucket as terraform/core (scripts/tf.sh passes ../core/backend.hcl), its own key.
  backend "s3" {
    key          = "cdc-lab/readers.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" { # credentials from AWS_PROFILE (SSO)
  region = var.aws_region

  default_tags {
    tags = {
      project    = "cdc-lab"
      managed_by = "terraform"
    }
  }
}
