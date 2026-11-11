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

resource "aws_iam_role_policy" "emr_job" {
  for_each = {
    read-reader-key = data.aws_iam_policy_document.read_reader_key.json
    artifacts       = data.aws_iam_policy_document.artifacts_rw.json
  }
  name   = each.key
  role   = aws_iam_role.emr_job.id
  policy = each.value
}
