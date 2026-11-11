#!/usr/bin/env bash
# Daily batch path + reconciliation:
#   1. COPY the day's raw S3 files into HIST.RAW_EVENTS (only files not loaded before)
#   2. rebuild HIST.TRANSACTION and HIST.TRANSACTION_ENRICHED (full history), run their tests
#   3. rebuild the RECON views and run the reconciliation tests (fails on any difference)
# Usage: scripts/run-batch.sh [YYYY-MM-DD | all]     default: yesterday (UTC)
set -euo pipefail
cd "$(dirname "$0")/.."

DAY="${1:-$(date -u -v-1d +%F 2>/dev/null || date -u -d yesterday +%F)}"   # BSD (macOS) or GNU date
if [[ "$DAY" == all ]]; then ARGS='{}'; else ARGS="{day: '$DAY'}"; fi

echo "== 1/3 load raw files ($DAY)"
scripts/dbt.sh run-operation load_raw_events --args "$ARGS"
echo "== 2/3 batch models"
scripts/dbt.sh build --select tag:batch
echo "== 3/3 reconciliation"
scripts/dbt.sh build --select tag:recon
