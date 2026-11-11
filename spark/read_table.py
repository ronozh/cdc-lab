"""Read an Iceberg table from Snowflake Horizon Catalog (Iceberg REST API) with Spark.

Run through spark/read.sh, which supplies the environment:
  SNOWFLAKE_ACCOUNT  <org>-<account>
  HORIZON_JWT        key-pair JWT of READER_SVC (exchanged for an access token by the Iceberg client)
  HORIZON_ROLE       Snowflake role used for the session
  AWS_REGION         region of the Snowflake account (where the table files live)
Usage: spark-submit read_table.py <SCHEMA.TABLE> [limit]
"""
import os
import sys

from pyspark.sql import SparkSession

table = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 10
catalog_uri = f"https://{os.environ['SNOWFLAKE_ACCOUNT']}.snowflakecomputing.com/polaris/api/catalog"
c = "spark.sql.catalog.horizon"  # catalog name inside Spark

spark = (
    SparkSession.builder.appName("horizon-read")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.defaultCatalog", "horizon")
    .config(c, "org.apache.iceberg.spark.SparkCatalog")
    .config(f"{c}.type", "rest")
    .config(f"{c}.uri", catalog_uri)
    .config(f"{c}.warehouse", "CDC_LAB")  # the Snowflake database, not a warehouse
    .config(f"{c}.credential", os.environ["HORIZON_JWT"])  # client secret for the OAuth client-credentials exchange
    .config(f"{c}.oauth2-server-uri", f"{catalog_uri}/v1/oauth/tokens")
    .config(f"{c}.scope", f"session:role:{os.environ['HORIZON_ROLE']}")
    .config(f"{c}.header.X-Iceberg-Access-Delegation", "vended-credentials")  # Horizon hands out short-lived S3 credentials
    .config(f"{c}.client.region", os.environ["AWS_REGION"])
    .config("spark.sql.iceberg.vectorization.enabled", "false")  # as in Snowflake's example
    .getOrCreate()
)
spark.sparkContext.setLogLevel("ERROR")

print(f"--- tables in {table.split('.')[0]}")
spark.sql(f"SHOW TABLES IN {table.split('.')[0]}").show(truncate=False)
df = spark.table(table)
print(f"--- {table}: {df.count()} rows, schema:")
df.printSchema()
df.show(limit, truncate=False)
spark.stop()
