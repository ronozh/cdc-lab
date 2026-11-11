#!/usr/bin/env bash
# Turn the lab back on (after scripts/lab-off.sh):
#   - start the Docker stack and wait until healthy (connectors resume from their saved offsets)
#   - resume the dynamic tables and the purge task
# The traffic generator is started by you:  uv run python src/generator.py
# Usage: scripts/lab-on.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SNOW="env -u SNOWFLAKE_PASSWORD snow sql -c ${SNOW_CONNECTION:-cdclab_terraform}"   # TERRAFORM_SVC, role SYSADMIN

echo "== Docker"
docker compose up -d --wait

echo "== connectors (waiting up to 60 s for all to be RUNNING)"
status() { curl -fs "localhost:8083/connectors?expand=status" \
  | jq -r 'to_entries[] | "  \(.key): \(.value.status.connector.state) / \([.value.status.tasks[].state] | join(","))"'; }
for _ in $(seq 1 20); do
  s=$(status || true)
  [[ -n "$s" ]] && ! grep -qvE ': RUNNING / RUNNING$' <<< "$s" && break
  sleep 3
done
echo "$s"

echo "== Snowflake: resume dynamic tables + purge task"
$SNOW -q "
  ALTER DYNAMIC TABLE IF EXISTS CDC_LAB.SILVER.TRANSACTION RESUME;
  ALTER DYNAMIC TABLE IF EXISTS CDC_LAB.GOLD.TRANSACTION_ENRICHED RESUME;
  ALTER TASK IF EXISTS CDC_LAB.BRONZE.PURGE_TRANSACTION_RAW RESUME;
" > /dev/null 2>&1
$SNOW -q "SHOW DYNAMIC TABLES IN DATABASE CDC_LAB" --format json 2>/dev/null | jq -r '.[] | "  \(.schema_name).\(.name): \(.scheduling_state)"'

echo "Next: uv run python src/generator.py   (traffic), scripts/check-local.sh   (local health)"
