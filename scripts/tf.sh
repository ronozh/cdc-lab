#!/usr/bin/env bash
# Run Terraform for one stack, with settings from .env (no terraform.tfvars needed):
#   core     S3 raw bucket + Snowflake (warehouse, database, roles, users, bronze, batch stage)
#   readers  optional AWS readers of gold: Lambda, EMR Serverless, SageMaker (scripts/aws-readers.sh)
# Usage: scripts/tf.sh <core|readers> <terraform arguments>      e.g. scripts/tf.sh core plan
# First time per stack: scripts/tf.sh <stack> init     (state bucket: terraform/core/backend.hcl)
set -euo pipefail
source "$(dirname "$0")/_env.sh"

STACK="${1:?usage: $0 <core|readers> <terraform arguments>}"; shift
[[ -d "terraform/$STACK" && "$STACK" != bootstrap ]] || { echo "no such stack: $STACK (core | readers)" >&2; exit 1; }

export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_snowflake_account="$SNOWFLAKE_ACCOUNT"                    # readers
export TF_VAR_snowflake_organization_name="${SNOWFLAKE_ACCOUNT%%-*}"    # core: <org>-<account> split at the first dash
export TF_VAR_snowflake_account_name="${SNOWFLAKE_ACCOUNT#*-}"

if [[ "${1:-}" == init ]]; then shift; set -- init -backend-config="$PWD/terraform/core/backend.hcl" "$@"; fi
# The Snowflake provider would (from v3) read SNOWFLAKE_ACCOUNT itself; it gets the account from the variables above.
exec env -u SNOWFLAKE_ACCOUNT terraform -chdir="terraform/$STACK" "$@"
