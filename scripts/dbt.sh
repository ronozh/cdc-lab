#!/usr/bin/env bash
# Run dbt for this project: settings from .env, dbt/profiles.yml.
# dbt runs in its own environment, made and cached by uv (kept apart from the project's packages, which it conflicts with).
# Usage: scripts/dbt.sh build --select realtime        (any dbt command)
set -euo pipefail
source "$(dirname "$0")/_env.sh"
exec uvx --python 3.13 --from dbt-core==1.12.6 --with dbt-snowflake==1.12.4 dbt "$@" --project-dir dbt --profiles-dir dbt
