# Roles (all roll up to SYSADMIN) and key-pair service users.
#   CDC_INGEST     ← KAFKA_SVC   Kafka connector: writes bronze
#   CDC_TRANSFORM  ← DBT_SVC     dbt: reads bronze / stage, builds REF, SILVER, GOLD, HIST, RECON
#   CDC_READER     ← READER_SVC  external engines (Spark via Horizon): read GOLD
# Grants that depend on objects of later phases live next to those objects (bronze.tf, raw.tf).

locals {
  roles = {
    CDC_INGEST    = "Kafka connector: writes bronze"
    CDC_TRANSFORM = "dbt: builds silver, gold, ref, hist, recon"
    CDC_READER    = "External engines: read gold"
  }
  users = {
    KAFKA_SVC  = { role = "CDC_INGEST", key = "kafka_svc", warehouse = null }
    DBT_SVC    = { role = "CDC_TRANSFORM", key = "dbt_svc", warehouse = "CDC_WH" }
    READER_SVC = { role = "CDC_READER", key = "reader_svc", warehouse = null }
  }
}

resource "snowflake_account_role" "this" {
  provider = snowflake.securityadmin
  for_each = local.roles
  name     = each.key
  comment  = "cdc-lab: ${each.value}"
}

resource "snowflake_grant_account_role" "to_sysadmin" {
  provider         = snowflake.securityadmin
  for_each         = local.roles
  role_name        = snowflake_account_role.this[each.key].name
  parent_role_name = "SYSADMIN"
}

# TYPE = SERVICE: key-pair only, no password / MFA / UI. Public key body read from <public_key_dir>/cdclab_<key>.pub.
resource "snowflake_service_user" "this" {
  provider          = snowflake.securityadmin
  for_each          = local.users
  name              = each.key
  default_role      = each.value.role
  default_warehouse = each.value.warehouse
  rsa_public_key = join("", [
    for line in split("\n", trimspace(file(pathexpand("${var.public_key_dir}/cdclab_${each.value.key}.pub")))) : line
    if !startswith(line, "-----")
  ])
  comment = "cdc-lab"

  depends_on = [snowflake_account_role.this]
}

resource "snowflake_grant_account_role" "to_user" {
  provider  = snowflake.securityadmin
  for_each  = local.users
  role_name = each.value.role
  user_name = snowflake_service_user.this[each.key].name

  depends_on = [snowflake_account_role.this]
}

# --- Common grants -------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  provider          = snowflake.securityadmin
  for_each          = local.roles
  account_role_name = snowflake_account_role.this[each.key].name
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.cdc.name
  }
}

# --- CDC_TRANSFORM -------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "transform_warehouse" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.this["CDC_TRANSFORM"].name
  privileges        = ["USAGE"] # dbt runs + dynamic table refreshes (the owner of a dynamic table can suspend / resume it)
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.cdc.name
  }
}

# dbt owns everything it builds in these schemas.
resource "snowflake_grant_privileges_to_account_role" "transform_schemas" {
  provider          = snowflake.securityadmin
  for_each          = toset(["SILVER", "GOLD", "REF", "HIST", "RECON"])
  account_role_name = snowflake_account_role.this["CDC_TRANSFORM"].name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE DYNAMIC TABLE", "CREATE ICEBERG TABLE"]
  on_schema {
    schema_name = snowflake_schema.this[each.key].fully_qualified_name
  }
}

# --- CDC_READER: GOLD only -----------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "reader_gold_usage" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.this["CDC_READER"].name
  privileges        = ["USAGE"]
  on_schema {
    schema_name = snowflake_schema.this["GOLD"].fully_qualified_name
  }
}

# Dynamic Iceberg tables take DYNAMIC TABLES future grants; plain Iceberg tables take ICEBERG TABLES.
resource "snowflake_grant_privileges_to_account_role" "reader_gold_future" {
  provider          = snowflake.securityadmin
  for_each          = toset(["DYNAMIC TABLES", "ICEBERG TABLES"])
  account_role_name = snowflake_account_role.this["CDC_READER"].name
  privileges        = ["SELECT"]
  on_schema_object {
    future {
      object_type_plural = each.key
      in_schema          = snowflake_schema.this["GOLD"].fully_qualified_name
    }
  }
}
