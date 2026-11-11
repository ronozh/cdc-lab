"""Lambda: today's sales summary from gold, read through Horizon Catalog with PyIceberg.

Environment (set by Terraform): SNOWFLAKE_ACCOUNT, HORIZON_SECRET_ID. Test: scripts/aws-readers.sh lambda
"""
import horizon


def handler(event, context):
    return horizon.summarize(horizon.read_gold())
