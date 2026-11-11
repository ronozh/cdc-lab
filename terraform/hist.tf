# Batch path input: Snowflake reads the raw S3 files through a storage integration (an IAM role Snowflake assumes)
# and an external stage. dbt (CDC_TRANSFORM) runs COPY INTO HIST.RAW_EVENTS from the stage.

locals {
  raw_reader_role     = "cdc-lab-snowflake-raw-reader"
  raw_reader_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.raw_reader_role}"
  raw_external_id     = "cdc-lab-raw" # our own external id → one apply, no two-pass setup
  raw_prefix          = "raw/cdc.public.transaction/"
}

# --- AWS: role Snowflake assumes to read raw/ -------------------------------------

data "aws_iam_policy_document" "raw_reader_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [snowflake_storage_integration_aws.raw.describe_output[0].iam_user_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.raw_external_id]
    }
  }
}

resource "aws_iam_role" "raw_reader" {
  name               = local.raw_reader_role
  description        = "Snowflake storage integration: read-only on the cdc-lab raw archive."
  assume_role_policy = data.aws_iam_policy_document.raw_reader_trust.json
}

data "aws_iam_policy_document" "raw_reader" {
  statement {
    sid       = "ReadRaw"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.raw.arn}/${local.raw_prefix}*"]
  }
  statement {
    sid       = "ListRaw"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.raw.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.raw_prefix}*"]
    }
  }
}

resource "aws_iam_role_policy" "raw_reader" {
  name   = "read-raw"
  role   = aws_iam_role.raw_reader.id
  policy = data.aws_iam_policy_document.raw_reader.json
}

# --- Snowflake: integration + stage -------------------------------------------------

resource "snowflake_storage_integration_aws" "raw" {
  provider                  = snowflake.accountadmin # only ACCOUNTADMIN can create integrations
  name                      = "CDC_RAW_S3"
  enabled                   = true
  storage_provider          = "S3"
  storage_aws_role_arn      = local.raw_reader_role_arn # role is created after; Snowflake only checks on use
  storage_aws_external_id   = local.raw_external_id
  storage_allowed_locations = ["s3://${aws_s3_bucket.raw.bucket}/${local.raw_prefix}"]
  comment                   = "cdc-lab: read-only access to the raw archive"
}

resource "snowflake_grant_privileges_to_account_role" "sysadmin_raw_integration" {
  provider          = snowflake.accountadmin
  account_role_name = "SYSADMIN"
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "INTEGRATION"
    object_name = snowflake_storage_integration_aws.raw.name
  }
}

# Files are gzip JSON (one event per line); the file format is given in the COPY (dbt macro load_raw_events).
resource "snowflake_stage_external_s3" "raw" {
  database            = snowflake_database.cdc.name
  schema              = snowflake_schema.this["HIST"].name
  name                = "RAW_STAGE"
  url                 = "s3://${aws_s3_bucket.raw.bucket}/${local.raw_prefix}"
  storage_integration = snowflake_storage_integration_aws.raw.name
  comment             = "cdc-lab raw archive: year=YYYY/month=MM/day=DD/hour=HH/<topic>+<partition>+<offset>.json.gz"

  depends_on = [snowflake_grant_privileges_to_account_role.sysadmin_raw_integration, aws_iam_role_policy.raw_reader]
}

resource "snowflake_grant_privileges_to_account_role" "transform_raw_stage" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.this["CDC_TRANSFORM"].name
  privileges        = ["USAGE"]
  on_schema_object {
    object_type = "STAGE"
    object_name = snowflake_stage_external_s3.raw.fully_qualified_name
  }
}
