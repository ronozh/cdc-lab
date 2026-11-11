"""Read Snowflake-managed Iceberg tables through Horizon Catalog (Iceberg REST) with PyIceberg.

Shared by the Streamlit dashboard, the Lambda function and the SageMaker notebook. No warehouse is used:
Horizon returns the table metadata plus short-lived S3 credentials, and PyIceberg reads the Parquet files itself.

Environment:
  SNOWFLAKE_ACCOUNT    <org>-<account>
  HORIZON_USER         Snowflake service user (default READER_SVC)
  HORIZON_ROLE         Snowflake role (default CDC_READER)
  HORIZON_KEY_FILE     private key file (local), or
  HORIZON_SECRET_ID    Secrets Manager secret holding the private key PEM (AWS)
  REPORT_TZ            time zone that defines "today" (default Australia/Sydney)
"""
import base64
import hashlib
import json
import os
import time
from datetime import datetime, time as day_start, timedelta
from zoneinfo import ZoneInfo

ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
USER = os.environ.get("HORIZON_USER", "READER_SVC")
ROLE = os.environ.get("HORIZON_ROLE", "CDC_READER")
CATALOG_URI = f"https://{ACCOUNT}.snowflakecomputing.com/polaris/api/catalog"
DATABASE = "CDC_LAB"
GOLD = "GOLD.TRANSACTION_ENRICHED"
COLUMNS = ("COMMITTED_AT", "CUSTOMER_TIER", "PRODUCT_TYPE", "NET_AMOUNT")  # all the summary needs


def private_key_pem() -> bytes:
    """The service user's private key: from a file (local) or Secrets Manager (AWS)."""
    if path := os.environ.get("HORIZON_KEY_FILE"):
        with open(os.path.expanduser(path), "rb") as f:
            return f.read()
    import boto3  # in the Lambda / SageMaker runtime

    return boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["HORIZON_SECRET_ID"])["SecretString"].encode()


def _rsa(key_pem: bytes):
    """(public key DER, sign function) with the `cryptography` package."""
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding

    key = serialization.load_pem_private_key(key_pem, password=None)
    public_der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return public_der, lambda data: key.sign(data, padding.PKCS1v15(), hashes.SHA256())


def mint_jwt(account: str, user: str, key_pem: bytes, lifetime_s: int = 3600, rsa=_rsa) -> str:
    """Snowflake key-pair JWT (RS256). Horizon exchanges it for an access token.

    `rsa` does the RSA work; Spark jobs pass one that uses the JVM (readers/spark_read.py), so they need no Python package.
    """
    public_der, sign = rsa(key_pem)
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(public_der).digest()).decode()
    name = f"{account.upper()}.{user.upper()}"
    now = int(time.time())

    def b64(raw: bytes) -> bytes:
        return base64.urlsafe_b64encode(raw).rstrip(b"=")

    signing_input = b".".join(
        b64(json.dumps(part).encode())
        for part in ({"alg": "RS256", "typ": "JWT"}, {"iss": f"{name}.{fingerprint}", "sub": name, "iat": now, "exp": now + lifetime_s})
    )
    return (signing_input + b"." + b64(sign(signing_input))).decode()


def catalog():
    """PyIceberg REST catalog on Horizon. The JWT is the OAuth client secret; data access uses vended S3 credentials."""
    from pyiceberg.catalog import load_catalog

    return load_catalog(
        "horizon",
        **{
            "type": "rest",
            "uri": CATALOG_URI,
            "warehouse": DATABASE,  # the Snowflake database, not a warehouse
            "credential": mint_jwt(ACCOUNT, USER, private_key_pem()),
            "oauth2-server-uri": f"{CATALOG_URI}/v1/oauth/tokens",
            "scope": f"session:role:{ROLE}",
            "header.X-Iceberg-Access-Delegation": "vended-credentials",
        },
    )


def read_gold():
    """Gold as an Arrow table (only the columns the summary needs)."""
    return catalog().load_table(GOLD).scan(selected_fields=COLUMNS).to_arrow()


def summarize(rows, day=None) -> dict:
    """One day's transaction count, count by customer tier and by product type, and total sales.

    A transaction belongs to the day (in REPORT_TZ) of its latest change, COMMITTED_AT: the Postgres commit time,
    a true instant. (EVENT_TS is the generator's wall clock without a time zone, so it can't be compared safely.)
    """
    import pyarrow as pa
    import pyarrow.compute as pc

    tz = ZoneInfo(os.environ.get("REPORT_TZ", "Australia/Sydney"))
    day = day or datetime.now(tz).date()
    start = datetime.combine(day, day_start.min, tz)
    committed = rows["COMMITTED_AT"]
    bounds = [pa.scalar(t, type=committed.type) for t in (start, start + timedelta(days=1))]
    today = rows.filter(pc.and_(pc.greater_equal(committed, bounds[0]), pc.less(committed, bounds[1])))

    def count_by(column: str) -> dict:
        counts = today.group_by(column).aggregate([([], "count_all")]).to_pylist()
        return dict(sorted(((r[column], r["count_all"]) for r in counts), key=lambda kv: (-kv[1], kv[0])))  # biggest first

    latest = pc.max(committed).as_py()
    return {
        "day": f"{day} ({tz.key})",
        "transactions": today.num_rows,
        "total_sales": float(pc.sum(today["NET_AMOUNT"]).as_py() or 0),
        "by_customer_tier": count_by("CUSTOMER_TIER"),
        "by_product_type": count_by("PRODUCT_TYPE"),
        "rows_in_gold": rows.num_rows,
        "latest_commit": latest.astimezone(tz).isoformat(timespec="seconds") if latest else None,
    }


if __name__ == "__main__":  # quick check: uv run --group readers python readers/horizon.py
    print(json.dumps(summarize(read_gold()), indent=2))
