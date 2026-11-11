#!/usr/bin/env bash
# Read a Snowflake-managed Iceberg table with Spark (in Docker) through Horizon Catalog.
# Usage: spark/read.sh GOLD.TRANSACTION_ENRICHED [limit]
# Needs: snow connection `cdclab_reader` (READER_SVC, key pair), Docker.
set -euo pipefail
cd "$(dirname "$0")"

TABLE="${1:?usage: $0 <SCHEMA.TABLE> [limit]}"
LIMIT="${2:-10}"
CONNECTION="${CONNECTION:-cdclab_reader}"
ICEBERG=1.9.1                                                    # version used in Snowflake's Spark example
IMAGE=spark:3.5.7-scala2.12-java17-python3-ubuntu                # official image: Spark 3.5 + Java 17 + Python

ACCOUNT=$(snow connection list --format json 2>/dev/null | jq -r --arg c "$CONNECTION" '.[] | select(.connection_name == $c) | .parameters.account')
ROLE=$(snow connection list --format json 2>/dev/null | jq -r --arg c "$CONNECTION" '.[] | select(.connection_name == $c) | .parameters.role')
JWT=$(env -u SNOWFLAKE_PASSWORD snow connection generate-jwt -c "$CONNECTION" 2>/dev/null | tail -1)   # valid 1 hour
[[ -n "$ACCOUNT" && -n "$ROLE" && "$JWT" == ey* ]] || { echo "could not read connection $CONNECTION or generate a JWT" >&2; exit 1; }

docker run --rm --user root \
  -e SNOWFLAKE_ACCOUNT="$ACCOUNT" -e HORIZON_ROLE="$ROLE" -e HORIZON_JWT="$JWT" -e AWS_REGION="${AWS_REGION:-ap-southeast-2}" \
  -v "$PWD:/app:ro" \
  -v cdc-lab-ivy:/root/.ivy2 \
  "$IMAGE" \
  /opt/spark/bin/spark-submit \
    --packages "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:$ICEBERG,org.apache.iceberg:iceberg-aws-bundle:$ICEBERG" \
    --conf spark.jars.ivy=/root/.ivy2 --conf spark.log.level=ERROR \
    /app/read_table.py "$TABLE" "$LIMIT" 2>&1 \
  | grep -vE '^(Ivy|:: |\s+(found|confirmed|downloading|\[SUCCESSFUL|org.apache.iceberg)|\s*-+$)|resolving dependencies|artifacts copied|loading settings|retrieving ::|jars for the packages|added as a dependency|modules in use| INFO |^\s*$'
