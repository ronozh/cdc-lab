locals {
  database = "CDC_LAB"
  schemas = {
    BRONZE = "Raw CDC events from Kafka (Iceberg, Snowflake storage)"
    SILVER = "Latest state per transaction, last 7 days (dynamic tables, dbt)"
    GOLD   = "Enriched transactions, last 7 days (dynamic tables, dbt)"
    REF    = "Static dimensions: customer, product (dbt seeds)"
    HIST   = "Batch path: full history from S3 (dbt)"
    RECON  = "Reconciliation between the real-time and batch paths (dbt)"
  }
}

# --- Compute -------------------------------------------------------------------

resource "snowflake_warehouse" "cdc" {
  name                = "CDC_WH"
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  comment             = "cdc-lab: dynamic table refreshes, dbt, queries"

  lifecycle {
    ignore_changes = [resource_monitor] # assigned below as ACCOUNTADMIN
  }
}

resource "snowflake_resource_monitor" "cdc" {
  provider        = snowflake.accountadmin
  name            = "CDC_RM"
  credit_quota    = var.credit_quota
  frequency       = "MONTHLY"
  start_timestamp = "IMMEDIATELY"
  notify_triggers = [80]
  suspend_trigger = 100
}

# Only ACCOUNTADMIN can assign a monitor; the warehouse stays owned by SYSADMIN.
resource "snowflake_execute" "warehouse_monitor" {
  for_each = toset([snowflake_warehouse.cdc.name, "TERRAFORM_WH"])
  provider = snowflake.accountadmin
  execute  = "ALTER WAREHOUSE \"${each.key}\" SET RESOURCE_MONITOR = ${snowflake_resource_monitor.cdc.fully_qualified_name}"
  revert   = "ALTER WAREHOUSE \"${each.key}\" UNSET RESOURCE_MONITOR"
}

# --- Storage -------------------------------------------------------------------

resource "snowflake_database" "cdc" {
  name    = local.database
  comment = "cdc-lab: Postgres CDC lakehouse"
}

resource "snowflake_schema" "this" {
  for_each = local.schemas
  database = snowflake_database.cdc.name
  name     = each.key
  comment  = each.value
}
