#!/usr/bin/env bash
# Create or update a Kafka Connect connector from a JSON file ({"name": ..., "config": {...}}).
# Idempotent: PUT /connectors/<name>/config creates the connector if missing, updates it otherwise.
# Usage: scripts/connect-apply.sh connect/pg-transaction-source.json
set -euo pipefail

FILE="${1:?usage: $0 <connector.json>}"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

NAME=$(jq -er '.name' "$FILE")                       # connector name from the file
jq -e '.config' "$FILE" > /dev/null                   # fail early if there is no config block

for _ in $(seq 1 30); do                              # wait up to ~60s for the Connect REST API
  curl -fs "$CONNECT_URL/" > /dev/null && break
  sleep 2
done
curl -fs "$CONNECT_URL/" > /dev/null || { echo "Connect REST API not reachable at $CONNECT_URL" >&2; exit 1; }

jq '.config' "$FILE" \
  | curl -fsS -X PUT -H "Content-Type: application/json" --data @- "$CONNECT_URL/connectors/$NAME/config" \
  | jq '{name, type, tasks: (.tasks | length)}'

echo "Waiting for $NAME to be RUNNING..."
for _ in $(seq 1 30); do                              # wait up to ~60s for connector + task
  STATUS=$(curl -fs "$CONNECT_URL/connectors/$NAME/status" || echo '{}')
  C=$(jq -r '.connector.state // "?"' <<< "$STATUS")
  T=$(jq -r '[.tasks[]?.state] | if length == 0 then "?" else join(",") end' <<< "$STATUS")
  if [[ "$C" == "RUNNING" && "$T" == "RUNNING" ]]; then
    echo "$NAME: connector=$C tasks=$T"
    exit 0
  fi
  if [[ "$C" == "FAILED" || "$T" == *FAILED* ]]; then
    echo "$NAME: connector=$C tasks=$T" >&2
    jq -r '.connector.trace // .tasks[0].trace // empty' <<< "$STATUS" | head -30 >&2
    exit 1
  fi
  sleep 2
done
echo "$NAME: not RUNNING after 60s (connector=$C tasks=$T)" >&2
exit 1
