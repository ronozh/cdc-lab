terraform {
  required_version = ">= 1.10" # use_lockfile (S3-native state locking)

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.21"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State bucket is shared with snowflake-lab (bucket + region in gitignored backend.hcl):
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "cdc-lab/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
