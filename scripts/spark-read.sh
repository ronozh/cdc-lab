#!/usr/bin/env bash
# Read a Snowflake-managed Iceberg table with Spark (in Docker) through Horizon Catalog, as READER_SVC.
# The same job runs on EMR Serverless (scripts/aws-readers.sh emr).
# Usage: scripts/spark-read.sh GOLD.TRANSACTION_ENRICHED [limit]
# Needs: .env (SNOWFLAKE_ACCOUNT), READER_SVC's private key (HORIZON_KEY_FILE), Docker.
set -euo pipefail
source "$(dirname "$0")/_env.sh"

TABLE="${1:?usage: $0 <SCHEMA.TABLE> [limit]}"
LIMIT="${2:-10}"
ICEBERG=1.9.1                                                    # version used in Snowflake's Spark example
IMAGE=spark:3.5.7-scala2.12-java17-python3-ubuntu                # official image: Spark 3.5 + Java 17 + Python

docker run --rm --user root \
  -e SNOWFLAKE_ACCOUNT -e AWS_REGION -e HORIZON_KEY_FILE=/key.p8 \
  -v "$PWD/readers:/app:ro" \
  -v "$HORIZON_KEY_FILE:/key.p8:ro" \
  -v cdc-lab-ivy:/root/.ivy2 \
  "$IMAGE" \
  /opt/spark/bin/spark-submit \
    --packages "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:$ICEBERG,org.apache.iceberg:iceberg-aws-bundle:$ICEBERG" \
    --conf spark.jars.ivy=/root/.ivy2 --conf spark.log.level=ERROR \
    --py-files /app/horizon.py \
    /app/spark_read.py "$TABLE" "$LIMIT" 2>&1 \
  | grep -vE '^(Ivy|:: |\s+(found|confirmed|downloading|\[SUCCESSFUL|org.apache.iceberg)|\s*-+$)|resolving dependencies|artifacts copied|loading settings|retrieving ::|jars for the packages|added as a dependency|modules in use| INFO |^\s*$'
