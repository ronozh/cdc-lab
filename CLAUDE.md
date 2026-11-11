# cdc-lab
Postgres → Debezium → Kafka → S3 raw + Snowflake Iceberg bronze → dynamic tables (silver/gold) + daily dbt batch + reconciliation.

- Responses: very very concise.
- Plans: `doc/plan/manual/`, one doc per phase, every command commented.
- No secrets in git (public repo).
