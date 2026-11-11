# Snowflake: TERRAFORM_SVC (key pair, created by terraform/bootstrap/terraform_svc.sql).
# One alias per system role, so each object is created with the least role that can do it.
locals {
  snowflake_auth = {
    organization_name = var.snowflake_organization_name
    account_name      = var.snowflake_account_name
    private_key       = file(pathexpand(var.snowflake_private_key_path))
  }
}

provider "snowflake" {
  role              = "SYSADMIN" # warehouse, database, schemas, bronze table, task, stage
  organization_name = local.snowflake_auth.organization_name
  account_name      = local.snowflake_auth.account_name
  user              = "TERRAFORM_SVC"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = local.snowflake_auth.private_key
  warehouse         = "TERRAFORM_WH"
}

provider "snowflake" {
  alias             = "securityadmin" # roles, users, grants
  role              = "SECURITYADMIN"
  organization_name = local.snowflake_auth.organization_name
  account_name      = local.snowflake_auth.account_name
  user              = "TERRAFORM_SVC"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = local.snowflake_auth.private_key
  warehouse         = "TERRAFORM_WH"
}

provider "snowflake" {
  alias             = "accountadmin" # resource monitor, storage integration
  role              = "ACCOUNTADMIN"
  organization_name = local.snowflake_auth.organization_name
  account_name      = local.snowflake_auth.account_name
  user              = "TERRAFORM_SVC"
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = local.snowflake_auth.private_key
  warehouse         = "TERRAFORM_WH"
}

# AWS: credentials from AWS_PROFILE (SSO).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = "cdc-lab"
      managed_by = "terraform"
    }
  }
}
