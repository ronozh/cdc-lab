#!/usr/bin/env bash
# Streamlit dashboard on gold (reads through Horizon as READER_SVC; no warehouse). http://localhost:8501
# Usage: scripts/dashboard.sh        Needs: .env (SNOWFLAKE_ACCOUNT), READER_SVC's private key (HORIZON_KEY_FILE)
set -euo pipefail
source "$(dirname "$0")/_env.sh"
exec uv run --group readers streamlit run readers/dashboard.py --browser.gatherUsageStats false "$@"
