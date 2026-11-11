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

output "notebook_instance" {
  value = aws_sagemaker_notebook_instance_lifecycle_configuration.readers.name # the instance has the same name
}
