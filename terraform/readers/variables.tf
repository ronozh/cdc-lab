variable "snowflake_account" {
  description = "Snowflake account identifier <org>-<account> (scripts/tf.sh passes SNOWFLAKE_ACCOUNT from .env)."
  type        = string
}

variable "aws_region" {
  description = "AWS region; same as the Snowflake account region."
  type        = string
  default     = "ap-southeast-2"
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
