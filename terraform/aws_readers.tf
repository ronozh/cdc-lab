# AWS readers of gold, all through Horizon Catalog (Iceberg REST) as READER_SVC:
#   Lambda + PyIceberg, EMR Serverless + PySpark, SageMaker notebook + PyIceberg.
# Each one reads READER_SVC's private key from Secrets Manager with its own IAM role, signs a JWT, and gets
# short-lived S3 credentials for the table files from Horizon. No Snowflake warehouse, no AWS access to Snowflake's bucket.
#
# Cost: Lambda, the EMR application (stops itself when idle), the VPC and the bucket cost nothing when unused; the secret
# costs $0.40 / month. The NAT gateway and the notebook instance bill per hour, so they exist only while
# var.aws_readers_on = true (scripts/aws-readers.sh on | off).

locals {
  readers_env = {
    SNOWFLAKE_ACCOUNT = "${var.snowflake_organization_name}-${var.snowflake_account_name}"
    HORIZON_SECRET_ID = aws_secretsmanager_secret.reader_key.name
  }
  artifacts = { # files the jobs load from S3
    "readers/horizon.py"       = "../readers/horizon.py"
    "readers/read_gold.ipynb"  = "../readers/read_gold.ipynb"
    "readers/requirements.txt" = "../readers/requirements.txt"
    "spark/read_table.py"      = "../spark/read_table.py"
    "lambda/lambda.zip"        = "../build/lambda.zip" # built by scripts/build-lambda.sh
  }
}

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

# --- Lambda + PyIceberg ----------------------------------------------------------------------------

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

resource "aws_iam_role" "lambda_reader" {
  name               = "cdc-lab-lambda-reader"
  assume_role_policy = data.aws_iam_policy_document.assume["lambda"].json
}

resource "aws_iam_role_policy" "lambda_reader_key" {
  name   = "read-reader-key"
  role   = aws_iam_role.lambda_reader.id
  policy = data.aws_iam_policy_document.read_reader_key.json
}

resource "aws_cloudwatch_log_group" "lambda_reader" {
  name              = "/aws/lambda/cdc-lab-gold-summary"
  retention_in_days = 14
}

data "aws_iam_policy_document" "lambda_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda_reader.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  name   = "write-logs"
  role   = aws_iam_role.lambda_reader.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}

# Not in a VPC: a Lambda function outside a VPC reaches the internet (Snowflake, S3) directly.
resource "aws_lambda_function" "gold_summary" {
  function_name    = "cdc-lab-gold-summary"
  role             = aws_iam_role.lambda_reader.arn
  runtime          = "python3.13"
  architectures    = ["arm64"] # the wheels in the package are Linux arm64
  handler          = "lambda_handler.handler"
  s3_bucket        = aws_s3_bucket.artifacts.id
  s3_key           = aws_s3_object.artifact["lambda/lambda.zip"].key
  source_code_hash = filebase64sha256(local.artifacts["lambda/lambda.zip"])
  memory_size      = 1024 # PyArrow; more memory also means more CPU for the cold start
  timeout          = 60

  environment {
    variables = local.readers_env
  }

  depends_on = [aws_cloudwatch_log_group.lambda_reader, aws_iam_role_policy.lambda_logs]
}

# --- Network for EMR Serverless --------------------------------------------------------------------
# An EMR Serverless application without a VPC can't reach the internet, and Horizon is a public endpoint. So: private
# subnets + NAT gateway. The VPC is free; the NAT gateway (hourly) exists only while var.aws_readers_on.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "readers" {
  cidr_block           = "10.20.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "cdc-lab-readers" }
}

resource "aws_internet_gateway" "readers" {
  vpc_id = aws_vpc.readers.id
  tags   = { Name = "cdc-lab-readers" }
}

resource "aws_subnet" "public" { # holds only the NAT gateway
  vpc_id            = aws_vpc.readers.id
  cidr_block        = "10.20.0.0/28"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "cdc-lab-readers-public" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.readers.id
  cidr_block        = cidrsubnet("10.20.0.0/24", 2, count.index + 1) # 10.20.0.64/26, 10.20.0.128/26
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "cdc-lab-readers-private-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.readers.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.readers.id
  }
  tags = { Name = "cdc-lab-readers-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.readers.id
  tags   = { Name = "cdc-lab-readers-private" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_eip" "nat" {
  count  = var.aws_readers_on ? 1 : 0
  domain = "vpc"
  tags   = { Name = "cdc-lab-readers-nat" }
}

resource "aws_nat_gateway" "readers" {
  count         = var.aws_readers_on ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "cdc-lab-readers" }

  depends_on = [aws_internet_gateway.readers]
}

resource "aws_route" "private_nat" {
  count                  = var.aws_readers_on ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.readers[0].id
}

# Free gateway endpoint: S3 traffic (table files, scripts, logs) skips the NAT gateway and its per-GB charge.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.readers.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "cdc-lab-readers-s3" }
}

resource "aws_security_group" "emr" {
  name        = "cdc-lab-emr-serverless"
  description = "EMR Serverless workers: outbound only"
  vpc_id      = aws_vpc.readers.id

  egress {
    description = "HTTPS: Horizon, S3, Secrets Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EMR Serverless + PySpark ----------------------------------------------------------------------

resource "aws_emrserverless_application" "spark" {
  name          = "cdc-lab-spark"
  release_label = var.emr_release_label
  type          = "spark"

  maximum_capacity { # a small ceiling: one driver + a few executors
    cpu    = "4 vCPU"
    memory = "16 GB"
  }
  auto_start_configuration { enabled = true }
  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 5 # no pre-initialized capacity, so an idle application costs nothing anyway
  }
  scheduler_configuration { # the service defaults, stated so that plans stay clean
    max_concurrent_runs   = 15
    queue_timeout_minutes = 360
  }
  network_configuration {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.emr.id]
  }
}

resource "aws_iam_role" "emr_job" {
  name               = "cdc-lab-emr-job"
  assume_role_policy = data.aws_iam_policy_document.assume["emr-serverless"].json
}

data "aws_iam_policy_document" "artifacts_rw" { # read code, write output; used by the EMR job role and the notebook role
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"] # list: needed for recursive copy / delete
    resources = [aws_s3_bucket.artifacts.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/readers/*", "${aws_s3_bucket.artifacts.arn}/spark/*"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/output/*"]
  }
}

resource "aws_iam_role_policy" "emr_job" {
  for_each = {
    read-reader-key = data.aws_iam_policy_document.read_reader_key.json
    artifacts       = data.aws_iam_policy_document.artifacts_rw.json
  }
  name   = each.key
  role   = aws_iam_role.emr_job.id
  policy = each.value
}

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
