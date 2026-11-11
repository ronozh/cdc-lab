# AWS readers of gold, all through Horizon Catalog (Iceberg REST) as READER_SVC:
#   Lambda + PyIceberg, EMR Serverless + PySpark, SageMaker notebook + PyIceberg.
# Each one reads READER_SVC's private key from Secrets Manager with its own IAM role, signs a JWT, and gets
# short-lived S3 credentials for the table files from Horizon. No Snowflake warehouse, no AWS access to Snowflake's bucket.
#
# Cost: Lambda, the EMR application (stops itself when idle), the VPC and the bucket cost nothing when unused; the secret
# costs $0.40 / month. The NAT gateway and the notebook instance bill per hour, so they exist only while
# var.aws_readers_on = true (scripts/aws-readers.sh on | off).
#
# Its own stack (state key cdc-lab/readers.tfstate): optional, AWS only, independent of terraform/core.

locals {
  readers_env = {
    SNOWFLAKE_ACCOUNT = var.snowflake_account
    HORIZON_SECRET_ID = aws_secretsmanager_secret.reader_key.name
  }
  artifacts = { # files the jobs load from S3
    "readers/horizon.py"       = "../../readers/horizon.py"
    "readers/read_gold.ipynb"  = "../../readers/read_gold.ipynb"
    "readers/requirements.txt" = "../../readers/requirements.txt"
    "readers/spark_read.py"    = "../../readers/spark_read.py"
    "lambda/lambda.zip"        = "../../build/lambda.zip" # built by scripts/build-lambda.sh
  }
}

data "aws_caller_identity" "current" {}

# --- Shared: private key secret, artifacts bucket -------------------------------------------------

# Terraform creates only the container, so the key never enters Terraform state. Value: scripts/aws-readers.sh key
resource "aws_secretsmanager_secret" "reader_key" {
  name                    = "cdc-lab/reader-svc-private-key"
  description             = "READER_SVC private key (PEM) for Horizon Catalog reads"
  recovery_window_in_days = 0 # lab: delete at once on destroy
}

data "aws_iam_policy_document" "read_reader_key" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.reader_key.arn]
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket        = "cdc-lab-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # only code and logs
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-job-output"
    status = "Enabled"
    filter { prefix = "output/" } # EMR logs, executed notebooks
    expiration { days = 14 }
  }
}

resource "aws_s3_object" "artifact" {
  for_each    = local.artifacts
  bucket      = aws_s3_bucket.artifacts.id
  key         = each.key
  source      = each.value
  source_hash = filemd5(each.value)
}

# --- Shared IAM documents --------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  for_each = toset(["lambda", "emr-serverless", "sagemaker"])
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["${each.key}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "artifacts_rw" { # read code, write output; used by the EMR job role and the notebook role
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"] # list: needed for recursive copy / delete
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/readers/*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/output/*"]
  }
}
