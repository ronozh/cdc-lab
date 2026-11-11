"""Read an Iceberg table from Snowflake Horizon Catalog (Iceberg REST API) with Spark.

Runs locally (spark/read.sh) and on EMR Serverless (scripts/aws-readers.sh emr). Environment:
  SNOWFLAKE_ACCOUNT  <org>-<account>
  HORIZON_ROLE       Snowflake role used for the session
  AWS_REGION         region of the Snowflake account (where the table files live)
  HORIZON_JWT        key-pair JWT of READER_SVC (exchanged for an access token by the Iceberg client), or
  HORIZON_SECRET_ID  Secrets Manager secret with the private key: the driver makes the JWT itself
                     (needs readers/horizon.py via --py-files)
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
    .config(f"{c}.oauth2-server-uri", f"{catalog_uri}/v1/oauth/tokens")
    .config(f"{c}.scope", f"session:role:{os.environ['HORIZON_ROLE']}")
    .config(f"{c}.header.X-Iceberg-Access-Delegation", "vended-credentials")  # Horizon hands out short-lived S3 credentials
    .config(f"{c}.client.region", os.environ["AWS_REGION"])
    .config("spark.sql.iceberg.vectorization.enabled", "false")  # as in Snowflake's example
    .getOrCreate()
)
spark.sparkContext.setLogLevel("ERROR")


def jvm_rsa(key_pem: bytes):
    """(public key DER, sign function) with the JVM's own crypto: EMR's Python has no `cryptography` package."""
    import base64

    jvm = spark.sparkContext._jvm
    der = base64.b64decode(b"".join(line for line in key_pem.splitlines() if not line.startswith(b"-----")))
    factory = jvm.java.security.KeyFactory.getInstance("RSA")
    key = factory.generatePrivate(jvm.java.security.spec.PKCS8EncodedKeySpec(der))
    spec = jvm.java.lang.Class.forName  # key specs are public classes; py4j can't call methods on the key objects themselves
    parts = factory.getKeySpec(key, spec("java.security.spec.RSAPrivateCrtKeySpec"))
    public = factory.generatePublic(jvm.java.security.spec.RSAPublicKeySpec(parts.getModulus(), parts.getPublicExponent()))
    public_der = bytes(factory.getKeySpec(public, spec("java.security.spec.X509EncodedKeySpec")).getEncoded())

    def sign(data: bytes) -> bytes:
        signature = jvm.java.security.Signature.getInstance("SHA256withRSA")
        signature.initSign(key)
        signature.update(data)
        return bytes(signature.sign())

    return public_der, sign


jwt = os.environ.get("HORIZON_JWT")
if not jwt:  # on AWS: no secret in the job parameters; the driver reads the key and signs
    import horizon

    jwt = horizon.mint_jwt(os.environ["SNOWFLAKE_ACCOUNT"], os.environ.get("HORIZON_USER", "READER_SVC"), horizon.private_key_pem(), lifetime_s=300, rsa=jvm_rsa)  # used once, right now
# OAuth client secret; set before the catalog is first used (it loads lazily). Spark logs changed settings in its event
# log: the job must run with spark.redaction.regex covering "credential" (scripts/aws-readers.sh emr does).
spark.conf.set(f"{c}.credential", jwt)

print(f"--- tables in {table.split('.')[0]}")
spark.sql(f"SHOW TABLES IN {table.split('.')[0]}").show(truncate=False)
df = spark.table(table)
print(f"--- {table}: {df.count()} rows, schema:")
df.printSchema()
df.show(limit, truncate=False)
spark.stop()
