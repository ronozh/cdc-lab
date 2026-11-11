# --- Lambda + PyIceberg ----------------------------------------------------------------------------

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
