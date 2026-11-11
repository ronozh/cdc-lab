#!/usr/bin/env bash
# Run dbt for this project: loads .env, uses dbt/profiles.yml and the dbt/.venv install.
# Usage: scripts/dbt.sh build --select realtime        (any dbt command)
# One-time install: uv venv dbt/.venv --python 3.13 && uv pip install -p dbt/.venv -r dbt/requirements.txt
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; source .env; set +a      # SNOWFLAKE_ACCOUNT (and the rest of .env)
unset SNOWFLAKE_PASSWORD         # key-pair only
cd dbt
exec .venv/bin/dbt "$@" --profiles-dir .
