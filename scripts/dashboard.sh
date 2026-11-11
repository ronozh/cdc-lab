#!/usr/bin/env bash
# Streamlit dashboard on gold (reads through Horizon as READER_SVC; no warehouse). http://localhost:8501
# Usage: scripts/dashboard.sh        Needs: .env (SNOWFLAKE_ACCOUNT), ~/.snowflake/keys/cdclab_reader_svc.p8
set -euo pipefail
cd "$(dirname "$0")/.."
SNOWFLAKE_ACCOUNT="$(grep '^SNOWFLAKE_ACCOUNT=' .env | cut -d= -f2 || true)"; export SNOWFLAKE_ACCOUNT
: "${SNOWFLAKE_ACCOUNT:?add SNOWFLAKE_ACCOUNT=<ORG>-<ACCOUNT> to .env}"
export HORIZON_KEY_FILE="${HORIZON_KEY_FILE:-$HOME/.snowflake/keys/cdclab_reader_svc.p8}"
exec uv run --group readers streamlit run readers/dashboard.py --browser.gatherUsageStats false "$@"
