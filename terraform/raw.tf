# Raw archive: every Kafka event as gzip JSON files, written by the S3 sink connector. Source of truth for the
# batch path. Default bucket settings (no versioning / Object Lock for now); never deleted by Terraform.
#   s3://<bucket>/raw/cdc.public.transaction/year=YYYY/month=MM/day=DD/hour=HH/<topic>+<partition>+<startOffset>.json.gz

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "raw" {
  bucket        = "cdc-lab-raw-${data.aws_caller_identity.current.account_id}" # account id keeps the name unique
  force_destroy = false                                                        # source of truth: never emptied implicitly
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Writer: the S3 sink connector (runs on your Mac, so it needs an access key) -----------------
# The secret key ends up in Terraform state (encrypted S3 bucket). Fine for a lab; on AWS compute use a role instead.

resource "aws_iam_user" "s3_sink" {
  name = "cdc-lab-s3-sink"
}

data "aws_iam_policy_document" "s3_sink" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.raw.arn]
  }
  statement {
    sid       = "WriteRaw"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
    resources = ["${aws_s3_bucket.raw.arn}/raw/*"]
  }
}

resource "aws_iam_user_policy" "s3_sink" {
  name   = "write-raw"
  user   = aws_iam_user.s3_sink.name
  policy = data.aws_iam_policy_document.s3_sink.json
}

resource "aws_iam_access_key" "s3_sink" {
  user = aws_iam_user.s3_sink.name
}
