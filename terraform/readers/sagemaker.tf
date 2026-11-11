# --- SageMaker notebook instance + PyIceberg (only while var.aws_readers_on) -----------------------

resource "aws_iam_role" "sagemaker" {
  name               = "cdc-lab-sagemaker-notebook"
  assume_role_policy = data.aws_iam_policy_document.assume["sagemaker"].json
}

data "aws_iam_policy_document" "sagemaker_logs" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"]
  }
}

resource "aws_iam_role_policy" "sagemaker" {
  for_each = {
    read-reader-key = data.aws_iam_policy_document.read_reader_key.json
    artifacts       = data.aws_iam_policy_document.artifacts_rw.json
    logs            = data.aws_iam_policy_document.sagemaker_logs.json
  }
  name   = each.key
  role   = aws_iam_role.sagemaker.id
  policy = each.value
}

# Runs at every start of the instance: fetch the notebook, install PyIceberg, run the notebook once and store the
# executed copy in S3 (that is the test). In the background, because a start script may take 5 minutes at most.
resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "readers" {
  name = "cdc-lab-readers"
  on_start = base64encode(templatefile("${path.module}/sagemaker_on_start.sh.tftpl", {
    bucket = aws_s3_bucket.artifacts.id
    region = var.aws_region
    env    = local.readers_env
  }))
}

resource "aws_sagemaker_notebook_instance" "readers" {
  count                 = var.aws_readers_on ? 1 : 0
  name                  = "cdc-lab-readers"
  role_arn              = aws_iam_role.sagemaker.arn
  instance_type         = "ml.t3.medium" # the smallest
  platform_identifier   = "notebook-al2023-v1"
  volume_size           = 5
  lifecycle_config_name = aws_sagemaker_notebook_instance_lifecycle_configuration.readers.name
  root_access           = "Disabled"
  # Default network: SageMaker-managed, with direct internet access (Snowflake, PyPI).

  depends_on = [aws_iam_role_policy.sagemaker, aws_s3_object.artifact]
}
