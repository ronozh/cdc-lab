output "snowflake_account" {
  description = "Account identifier <org>-<account>."
  value       = "${var.snowflake_organization_name}-${var.snowflake_account_name}"
}

output "horizon_catalog_uri" {
  description = "Iceberg REST endpoint of Horizon Catalog (external engines)."
  value       = "https://${var.snowflake_organization_name}-${var.snowflake_account_name}.snowflakecomputing.com/polaris/api/catalog"
}

output "raw_bucket" {
  description = "S3 bucket of the raw archive."
  value       = aws_s3_bucket.raw.bucket
}

output "s3_sink_access_key_id" {
  description = "Access key of the S3 sink connector (→ .env S3_SINK_ACCESS_KEY_ID)."
  value       = aws_iam_access_key.s3_sink.id
}

output "s3_sink_secret_access_key" {
  description = "Secret of the S3 sink connector (→ .env S3_SINK_SECRET_ACCESS_KEY). terraform output -raw s3_sink_secret_access_key"
  value       = aws_iam_access_key.s3_sink.secret
  sensitive   = true
}

output "artifacts_bucket" {
  description = "S3 bucket for job code and output (AWS readers)."
  value       = aws_s3_bucket.artifacts.bucket
}

output "reader_key_secret" {
  description = "Secrets Manager secret that holds READER_SVC's private key."
  value       = aws_secretsmanager_secret.reader_key.name
}

output "lambda_function" {
  value = aws_lambda_function.gold_summary.function_name
}

output "emr_application_id" {
  value = aws_emrserverless_application.spark.id
}

output "emr_job_role_arn" {
  value = aws_iam_role.emr_job.arn
}
