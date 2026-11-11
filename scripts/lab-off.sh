#!/usr/bin/env bash
# Turn the lab off to stop spending credits. Data is kept (Postgres + Kafka volumes, S3, Snowflake tables).
#   - stop the traffic generator
#   - suspend the dynamic tables (no more refreshes → CDC_WH auto-suspends after 60 s) and the purge task
#   - stop the Docker stack (Postgres, Kafka, Connect)
#   - warn if the AWS readers (phase 11) are still on
# Usage: scripts/lab-off.sh          Undo: scripts/lab-on.sh
set -uo pipefail
cd "$(dirname "$0")/.."
SNOW="env -u SNOWFLAKE_PASSWORD snow sql -c ${SNOW_CONNECTION:-cdclab_terraform}"   # TERRAFORM_SVC, role SYSADMIN

echo "== generator"
pkill -f "src/generator.py" && echo "stopped" || echo "not running"

echo "== Snowflake: suspend dynamic tables + purge task"
$SNOW -q "
  ALTER DYNAMIC TABLE IF EXISTS CDC_LAB.GOLD.TRANSACTION_ENRICHED SUSPEND;
  ALTER DYNAMIC TABLE IF EXISTS CDC_LAB.SILVER.TRANSACTION SUSPEND;
  ALTER TASK IF EXISTS CDC_LAB.BRONZE.PURGE_TRANSACTION_RAW SUSPEND;
" > /dev/null 2>&1 && echo "suspended" || echo "WARN: could not suspend (check: snow sql -c cdclab_terraform -q 'show dynamic tables in database CDC_LAB')"

echo "== Docker"
docker compose stop

echo "== AWS readers (hourly-billed: NAT gateway, notebook instance)"
if nat=$(aws ec2 describe-nat-gateways --region "${AWS_REGION:-ap-southeast-2}" --filter Name=tag:Name,Values=cdc-lab-readers Name=state,Values=pending,available --query 'length(NatGateways)' --output text 2>/dev/null); then
  [[ "$nat" == 0 ]] && echo "off" || echo "WARN: still ON and billing. Run: scripts/aws-readers.sh off"
else
  echo "WARN: could not check (AWS login?). If you ran 'scripts/aws-readers.sh on', run: scripts/aws-readers.sh off"
fi

echo "== state"
$SNOW -q "SHOW DYNAMIC TABLES IN DATABASE CDC_LAB" --format json 2>/dev/null | jq -r '.[] | "  \(.schema_name).\(.name): \(.scheduling_state)"'
$SNOW -q "SHOW WAREHOUSES LIKE 'CDC_WH'" --format json 2>/dev/null | jq -r '.[] | "  CDC_WH: \(.state) (auto-suspends 60 s after the last query)"'
