variable "snowflake_organization_name" {
  description = "Snowflake organization (first part of <org>-<account>)."
  type        = string
}

variable "snowflake_account_name" {
  description = "Snowflake account name (second part of <org>-<account>)."
  type        = string
}

variable "snowflake_private_key_path" {
  description = "TERRAFORM_SVC private key (PKCS#8, unencrypted)."
  type        = string
  default     = "~/.snowflake/keys/cdclab_terraform_svc.p8"
}

variable "public_key_dir" {
  description = "Folder with cdclab_<user>.pub public keys of the service users."
  type        = string
  default     = "~/.snowflake/keys"
}

variable "aws_region" {
  description = "AWS region; same as the Snowflake account region (no cross-region transfer cost)."
  type        = string
  default     = "ap-southeast-2"
}

variable "credit_quota" {
  description = "Monthly credit quota for the resource monitor on CDC_WH; warehouses suspend at 100%."
  type        = number
  default     = 25
}

variable "aws_readers_on" {
  description = "Create the hourly-billed parts of the AWS readers: NAT gateway (EMR Serverless) and SageMaker notebook instance. scripts/aws-readers.sh on | off."
  type        = bool
  default     = false
}

variable "emr_release_label" {
  description = "EMR Serverless release (Spark 3.5 + bundled Iceberg runtime)."
  type        = string
  default     = "emr-7.14.0"
}
