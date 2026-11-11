# Shared setup, sourced by the other scripts:  source "$(dirname "$0")/_env.sh"
#   - cd to the repo root
#   - load .env (the one place for local settings; see .env.example)
#   - key-pair only: drop SNOWFLAKE_PASSWORD so snow / dbt / Terraform never fall back to it
cd "$(dirname "${BASH_SOURCE[0]}")/.."
set -a; source .env; set +a
unset SNOWFLAKE_PASSWORD
: "${SNOWFLAKE_ACCOUNT:?add SNOWFLAKE_ACCOUNT=<ORG>-<ACCOUNT> to .env}"
export AWS_REGION="${AWS_REGION:-ap-southeast-2}"                                   # same region as the Snowflake account
export HORIZON_KEY_FILE="${HORIZON_KEY_FILE:-$HOME/.snowflake/keys/cdclab_reader_svc.p8}"   # READER_SVC private key
export SNOW_CONNECTION="${SNOW_CONNECTION:-cdclab_terraform}"                       # snow CLI connection (TERRAFORM_SVC, SYSADMIN)
