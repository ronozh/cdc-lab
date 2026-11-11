#!/usr/bin/env bash
# AWS readers of gold through Horizon Catalog: Lambda + PyIceberg, EMR Serverless + PySpark, SageMaker + PyIceberg.
# Infrastructure: terraform/readers/ (its own stack). Needs: AWS_PROFILE, scripts/build-lambda.sh run once.
# Usage: scripts/aws-readers.sh <command>
#   (first time: off, key, on: the notebook instance needs the key at its first start)
#   on         terraform apply with the hourly-billed parts: NAT gateway (EMR) + notebook instance (SageMaker)
#   off        terraform apply without them (Lambda, EMR application, VPC, bucket, secret stay: no idle cost)
#   key        put READER_SVC's private key into Secrets Manager (once, and after a key rotation)
#   lambda     invoke the function, print its JSON summary
#   emr        run readers/spark_read.py on EMR Serverless, print the driver output            (needs: on)
#   sagemaker  print the result of the notebook that the instance runs at every start        (needs: on)
set -euo pipefail
source "$(dirname "$0")/_env.sh"
tf() { scripts/tf.sh readers "$@"; }
out() { tf output -raw "$1"; }
TABLE="${TABLE:-GOLD.TRANSACTION_ENRICHED}"

case "${1:-}" in
  on)  tf apply -var aws_readers_on=true "${@:2}" ;;
  off) tf apply -var aws_readers_on=false "${@:2}" ;;

  key)
    aws secretsmanager put-secret-value --secret-id "$(out reader_key_secret)" \
      --secret-string "file://$HORIZON_KEY_FILE" --query VersionId --output text ;;

  lambda)
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    err=$(aws lambda invoke --function-name "$(out lambda_function)" "$tmp" --query FunctionError --output text)
    jq . "$tmp"                                                    # the summary, or the error message
    [[ "$err" == None ]] || { echo "function error: $err" >&2; exit 1; } ;;

  emr)
    app=$(out emr_application_id); bucket=$(out artifacts_bucket)
    nat=$(aws ec2 describe-nat-gateways --filter Name=tag:Name,Values=cdc-lab-readers Name=state,Values=available --query 'length(NatGateways)' --output text)
    [[ "$nat" != 0 ]] || { echo "no NAT gateway: the job could not reach Horizon. Run: $0 on" >&2; exit 1; }
    env_conf=""                                                   # driver environment: where Horizon is, where the key is
    for kv in SNOWFLAKE_ACCOUNT="$SNOWFLAKE_ACCOUNT" HORIZON_SECRET_ID="$(out reader_key_secret)" \
              AWS_REGION="$AWS_REGION" AWS_DEFAULT_REGION="$AWS_REGION"; do
      env_conf+=" --conf spark.emr-serverless.driverEnv.$kv"
    done
    # Iceberg: the runtime jar that ships with the EMR release. Small fixed size: 1 driver + 1 executor.
    params="--py-files s3://$bucket/readers/horizon.py --conf spark.jars=/usr/share/aws/iceberg/lib/iceberg-spark3-runtime.jar"
    params+=" --conf spark.dynamicAllocation.enabled=false --conf spark.executor.instances=1"
    # Keep the JWT out of the Spark event log: redact every setting whose name contains "credential".
    redact="(?i)secret|password|token|access[.]key|credential"
    params+=" --conf spark.redaction.regex=$redact --conf spark.sql.redaction.options.regex=$redact"
    params+=" --conf spark.driver.cores=1 --conf spark.driver.memory=2g --conf spark.executor.cores=1 --conf spark.executor.memory=2g$env_conf"
    job=$(aws emr-serverless start-job-run --application-id "$app" --execution-role-arn "$(out emr_job_role_arn)" \
      --name "read-$TABLE" --execution-timeout-minutes 15 \
      --job-driver "$(jq -n --arg e "s3://$bucket/readers/spark_read.py" --arg t "$TABLE" --arg p "$params" \
        '{sparkSubmit: {entryPoint: $e, entryPointArguments: [$t, "5"], sparkSubmitParameters: $p}}')" \
      --configuration-overrides "$(jq -n --arg l "s3://$bucket/output/emr/" '{monitoringConfiguration: {s3MonitoringConfiguration: {logUri: $l}}}')" \
      --query jobRunId --output text)
    echo "job $job (first run after idle: ~2-3 min to start)"
    while state=$(aws emr-serverless get-job-run --application-id "$app" --job-run-id "$job" --query jobRun.state --output text);
          [[ ! "$state" =~ ^(SUCCESS|FAILED|CANCELLED)$ ]]; do echo "  $state"; sleep 15; done
    echo "== $state"
    logs="s3://$bucket/output/emr/applications/$app/jobs/$job/SPARK_DRIVER"
    aws s3 cp "$logs/stdout.gz" - 2>/dev/null | gunzip || echo "(no driver output)"
    if [[ "$state" != SUCCESS ]]; then
      aws emr-serverless get-job-run --application-id "$app" --job-run-id "$job" --query jobRun.stateDetails --output text
      echo "driver log: aws s3 cp $logs/stderr.gz - | gunzip | less"; exit 1
    fi ;;

  sagemaker)
    bucket=$(out artifacts_bucket); name=$(out notebook_instance)
    aws sagemaker wait notebook-instance-in-service --notebook-instance-name $name   # the start script has begun: old result removed
    echo "waiting for the start script's result (up to 10 min) ..."
    for _ in $(seq 1 60); do
      aws s3 cp "s3://$bucket/output/sagemaker/run-readers.log" - 2>/dev/null | tail -1 | grep -qE '^(DONE|FAILED)' && break; sleep 10
    done
    result=$(aws s3 cp "s3://$bucket/output/sagemaker/run-readers.log" - 2>/dev/null | tail -5 || true)
    echo "$result"
    [[ "$(tail -1 <<< "$result")" == DONE ]] || { echo "the notebook run did not finish: see the log above (s3://$bucket/output/sagemaker/run-readers.log)" >&2; exit 1; }
    echo "== outputs of the executed notebook"
    aws s3 cp "s3://$bucket/output/sagemaker/read_gold.executed.ipynb" - \
      | jq -r '.cells[] | select(.cell_type == "code") | .outputs[] | (.text // .data["text/plain"] // [.evalue]) | join("")'
    echo "open Jupyter: aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name $name --query AuthorizedUrl --output text" ;;

  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
