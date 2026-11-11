# Bronze: raw CDC events from Kafka, one row per event, written by the Snowflake Kafka connector (KAFKA_SVC).
# Iceberg v3 on Snowflake storage (no external volume). VARIANT columns need v3.
#   RECORD_METADATA  Kafka: topic, partition, offset, key, CreateTime, ...
#   RECORD_CONTENT   the Debezium event: before, after, op, source, ts_ms
# No Terraform resource exists for Iceberg tables, so plain SQL (create on apply, drop on destroy).

locals {
  bronze_table = "${snowflake_database.cdc.name}.${snowflake_schema.this["BRONZE"].name}.TRANSACTION_RAW"
}

resource "snowflake_execute" "bronze_table" {
  execute = <<-SQL
    CREATE ICEBERG TABLE IF NOT EXISTS ${local.bronze_table} (
      RECORD_METADATA VARIANT,
      RECORD_CONTENT  VARIANT
    )
    CATALOG = 'SNOWFLAKE'
    EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED'
    ICEBERG_VERSION = 3
    COMMENT = 'cdc-lab: raw Debezium events from cdc.public.transaction (Kafka connector v4)'
  SQL
  revert  = "DROP TABLE IF EXISTS ${local.bronze_table}"
}

# Without error logging the v4 connector silently drops records it can't insert; with it they go to the error table.
# Separate from the CREATE so changing it never recreates (= empties) bronze.
resource "snowflake_execute" "bronze_error_logging" {
  execute = "ALTER ICEBERG TABLE ${local.bronze_table} SET ERROR_LOGGING = TRUE"
  revert  = "ALTER ICEBERG TABLE IF EXISTS ${local.bronze_table} SET ERROR_LOGGING = FALSE"

  depends_on = [snowflake_execute.bronze_table]
}

# --- 7-day retention -------------------------------------------------------------
# Bronze is a copy of the S3 raw archive (phase 6), so it only keeps a week. Silver / gold filter the same window.
# Serverless task (no warehouse to wake); SYSADMIN owns it and needs these two account privileges.
resource "snowflake_grant_privileges_to_account_role" "sysadmin_tasks" {
  provider          = snowflake.accountadmin
  account_role_name = "SYSADMIN"
  privileges        = ["EXECUTE TASK", "EXECUTE MANAGED TASK"]
  on_account        = true
}

resource "snowflake_execute" "bronze_purge_task" {
  execute = <<-SQL
    CREATE OR REPLACE TASK ${snowflake_database.cdc.name}.${snowflake_schema.this["BRONZE"].name}.PURGE_TRANSACTION_RAW
      SCHEDULE = 'USING CRON 0 3 * * * UTC'
      USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
      COMMENT = 'cdc-lab: delete bronze events older than 7 days (S3 keeps them)'
    AS
      DELETE FROM ${local.bronze_table}
      WHERE TO_TIMESTAMP_LTZ(RECORD_METADATA:CreateTime::NUMBER, 3) < DATEADD(day, -7, CURRENT_TIMESTAMP())
  SQL
  revert  = "DROP TASK IF EXISTS ${snowflake_database.cdc.name}.${snowflake_schema.this["BRONZE"].name}.PURGE_TRANSACTION_RAW"

  depends_on = [snowflake_execute.bronze_table, snowflake_grant_privileges_to_account_role.sysadmin_tasks]
}

# Tasks are created suspended. scripts/lab-on.sh / lab-off.sh resume / suspend it with the rest of the lab.

# --- Grants --------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "bronze_usage" {
  provider          = snowflake.securityadmin
  for_each          = toset(["CDC_INGEST", "CDC_TRANSFORM"])
  account_role_name = snowflake_account_role.this[each.key].name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.this["BRONZE"].fully_qualified_name
  }
}

# Connector: append rows. The v4 connector streams through the table's default pipe (no CREATE PIPE needed).
resource "snowflake_execute" "bronze_grants" {
  execute = <<-SQL
    BEGIN
      GRANT INSERT, SELECT ON TABLE ${local.bronze_table} TO ROLE ${snowflake_account_role.this["CDC_INGEST"].name};
      GRANT SELECT ON TABLE ${local.bronze_table} TO ROLE ${snowflake_account_role.this["CDC_TRANSFORM"].name};
    END;
  SQL
  revert  = "SELECT 1" # dropping the table removes its grants

  depends_on = [snowflake_execute.bronze_table]
}
