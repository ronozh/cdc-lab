#!/usr/bin/env bash
# Health check of the local stack: Postgres → Debezium → Kafka.
# FAIL = broken or data lost (exit 1). WARN = works, but worth knowing (e.g. duplicate events, which are
# expected after an unclean interruption: delivery is at-least-once).
# Usage: scripts/check-local.sh        (run from anywhere; stack must be up)
set -uo pipefail
cd "$(dirname "$0")/.."

TOPIC=cdc.public.transaction
CONNECTOR=pg-transaction-source
SLOT=debezium_transaction
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
WAIT_SEC="${WAIT_SEC:-60}"                                     # how long to wait for the connector / slot after a (re)start
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0

pass() { printf '  PASS  %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
psql_q() { docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -c "$1"' _ "$1"; }   # run one query, plain output
kafka() { docker compose exec -T kafka "$@"; }
connector_state() { curl -fs "$CONNECT_URL/connectors/$CONNECTOR/status" | jq -r '(.connector.state // "missing") + " " + ([.tasks[]?.state] | join(","))' 2>/dev/null || echo "unreachable"; }
slot_state() { psql_q "select active::text || ' ' || coalesce(wal_status, '?') from pg_replication_slots where slot_name = '$SLOT'" 2>/dev/null; }
health() { docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$1" 2>/dev/null || echo missing; }
all_healthy() { for c in cdc-postgres cdc-kafka cdc-connect; do [[ "$(health "$c")" == healthy ]] || return 1; done; }

# Right after `up` / a restart: containers become healthy first, then the task runs and the slot is re-attached.
# Wait (up to WAIT_SEC) for all of it before judging, so a check started right after a restart doesn't fail falsely.
for _ in $(seq 1 $((WAIT_SEC / 3))); do
  all_healthy && [[ "$(connector_state)" == "RUNNING RUNNING" && "$(slot_state)" == true\ * ]] && break
  sleep 3
done

echo "Containers"
for c in cdc-postgres cdc-kafka cdc-connect; do
  h=$(health "$c")
  [[ "$h" == healthy ]] && pass "$c healthy" || fail "$c $h"
done
if docker inspect -f '{{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}' cdc-kafka 2>/dev/null | grep -q 'cdc-lab_kafkadata:/var/lib/kafka/data'; then
  pass "Kafka data on volume cdc-lab_kafkadata"
else
  fail "Kafka data not on volume cdc-lab_kafkadata (topics lost on down)"
fi

echo "Postgres"
v=$(psql_q "show wal_level"); [[ "$v" == logical ]] && pass "wal_level=logical" || fail "wal_level=$v"
v=$(psql_q "show max_slot_wal_keep_size"); [[ "$v" != -1 ]] && pass "max_slot_wal_keep_size=$v" || warn "max_slot_wal_keep_size unlimited"
v=$(psql_q "select relreplident from pg_class where oid = 'public.transaction'::regclass"); [[ "$v" == f ]] && pass "transaction REPLICA IDENTITY FULL" || fail "relreplident=$v (want f)"
v=$(slot_state)
[[ "$v" == "true reserved" || "$v" == "true extended" ]] && pass "slot $SLOT active ($v)" || fail "slot $SLOT: '${v:-missing}'"
v=$(psql_q "select string_agg(slot_name || '(' || pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) || ')', ', ') from pg_replication_slots where slot_name <> '$SLOT'")
[[ -z "$v" ]] && pass "no other replication slots" || warn "other slots hold WAL: $v"

echo "Kafka Connect"
v=$(connector_state)
[[ "$v" == "RUNNING RUNNING" ]] && pass "$CONNECTOR connector/task: $v" || fail "$CONNECTOR connector/task: $v"

echo "Kafka topic $TOPIC"
v=$(kafka /opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka:9092 --entity-type topics --entity-name "$TOPIC" --describe --all 2>/dev/null \
    | awk '{print $1}' | grep -E '^retention\.ms=' | cut -d= -f2)
[[ "$v" == -1 ]] && pass "retention.ms=-1 (kept forever)" || fail "retention.ms=${v:-?} (want -1)"

# Postgres state first, then read the topic: every state committed before now must be in Kafka.
psql_q "select transaction_id || chr(9) || status from transaction" | sort -u > "$TMP/pg_state"
sleep 5                                                       # give Debezium time to ship the latest commits
end=$(kafka /opt/kafka/bin/kafka-get-offsets.sh --bootstrap-server kafka:9092 --topic "$TOPIC" 2>/dev/null | awk -F: '{s += $3} END {print s + 0}')
# --max-messages stops at the end offset noted above (the generator keeps writing, so an idle timeout alone never fires);
# --timeout-ms is only a safety net. One fixed group with auto-commit off: it never stores an offset, so every
# run reads from the beginning, and runs don't pile up random console-consumer-* groups.
if [[ "$end" -gt 0 ]]; then
  kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic "$TOPIC" \
    --group check-local --from-beginning --max-messages "$end" --timeout-ms 20000 \
    --command-property enable.auto.commit=false 2>/dev/null | grep "^{" \
    | jq -r '[.op, (.after // .before).transaction_id, (.after.status // ""), (.source.lsn | tostring)] | @tsv' > "$TMP/events"
else
  : > "$TMP/events"
fi
n=$(wc -l < "$TMP/events" | tr -d ' ')
[[ "$n" -eq "$end" && "$end" -gt 0 ]] && pass "read $n events (end offset $end)" || fail "read $n events, end offset $end"
awk -F'\t' '{c[$1]++} END {for (o in c) printf "%s=%d ", o, c[o]; print ""}' "$TMP/events" | sed 's/^/        ops: /'

# Loss check: each row's current status must appear in some event for that row.
# (Statuses only move forward, so a later update in Kafka does not hide an earlier captured one.)
cut -f2,3 "$TMP/events" | sort -u > "$TMP/topic_state"
missing=$(comm -23 "$TMP/pg_state" "$TMP/topic_state" | wc -l | tr -d ' ')
total=$(wc -l < "$TMP/pg_state" | tr -d ' ')
[[ "$missing" == 0 ]] && pass "all $total rows: current state is in Kafka (no lost events)" \
  || fail "$missing of $total rows: current state missing in Kafka, e.g. $(comm -23 "$TMP/pg_state" "$TMP/topic_state" | head -3 | tr '\t\n' ': ')"

# Duplicate checks: WARN only. Downstream dedups by (transaction_id, source.lsn).
dup=$(awk -F'\t' '$1 != "r"' "$TMP/events" | sort | uniq -d | wc -l | tr -d ' ')
[[ "$dup" == 0 ]] && pass "no replayed c/u events" || warn "$dup c/u events replayed (same id + LSN); normal after a crash or Postgres restart"
dup=$(awk -F'\t' '$1 == "r" {print $2}' "$TMP/events" | sort | uniq -d | wc -l | tr -d ' ')
[[ "$dup" == 0 ]] && pass "single snapshot (no duplicate r events)" || warn "$dup ids have several r events: a re-snapshot happened (expected only after a recovery)"

echo
if [[ "$FAILS" == 0 ]]; then echo "ALL CHECKS PASSED"; else echo "$FAILS CHECK(S) FAILED"; exit 1; fi
