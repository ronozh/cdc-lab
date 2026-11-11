#!/usr/bin/env bash
# Build the Lambda package: build/lambda.zip = PyIceberg + PyArrow + cryptography (Linux arm64 wheels) + our two files.
# Terraform uploads it (terraform/readers/lambda.tf). boto3 is already in the Lambda runtime.
# Usage: scripts/build-lambda.sh
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/lambda build/lambda.zip && mkdir -p build/lambda
uv pip install --quiet --target build/lambda \
  --python-platform aarch64-manylinux_2_28 --python-version 3.13 --only-binary :all: \
  -r readers/requirements.txt
cp readers/horizon.py readers/lambda_handler.py build/lambda/
find build/lambda -name __pycache__ -prune -exec rm -rf {} +                      # smaller package
rm -rf build/lambda/bin build/lambda/pyarrow/tests build/lambda/pyarrow/include   # not needed at run time
(cd build/lambda && zip -qr -X ../lambda.zip .)
echo "build/lambda.zip: $(du -h build/lambda.zip | cut -f1) zipped, $(du -sh build/lambda | cut -f1) unzipped (Lambda limit: 250 MB unzipped)"
