#!/usr/bin/env bash
# Download Kafka Connect sink plugins (pinned versions) into connect/plugins/<plugin>/.
# The folders are gitignored and mounted into the connect container (docker-compose.yml).
# Usage: scripts/download-plugins.sh      (safe to re-run: existing files are kept)
set -euo pipefail
cd "$(dirname "$0")/../connect/plugins"

MAVEN=https://repo1.maven.org/maven2

fetch() {  # fetch <folder> <url>
  local dir=$1 url=$2 file
  file="$dir/$(basename "$url")"
  mkdir -p "$dir"
  [[ -s "$file" ]] && { echo "have  $file"; return; }
  echo "get   $file"
  curl -fsSL -o "$file.part" "$url" && mv "$file.part" "$file"
}

# Snowflake sink v4 (high-performance Snowpipe Streaming). Bouncy Castle FIPS is "provided" scope: ship it next to the jar.
fetch snowflake "$MAVEN/com/snowflake/snowflake-kafka-connector/4.2.3/snowflake-kafka-connector-4.2.3.jar"
fetch snowflake "$MAVEN/org/bouncycastle/bcpkix-fips/2.1.12/bcpkix-fips-2.1.12.jar"
fetch snowflake "$MAVEN/org/bouncycastle/bcutil-fips/2.1.7/bcutil-fips-2.1.7.jar"
fetch snowflake "$MAVEN/org/bouncycastle/bc-fips/2.1.3/bc-fips-2.1.3.jar"

# Confluent S3 sink (Confluent Community License: free to self-host). Zip from Confluent Hub; only lib/*.jar is needed.
S3_VERSION=12.1.15
if ! ls s3/kafka-connect-s3-"$S3_VERSION".jar > /dev/null 2>&1; then
  fetch .download "https://hub-downloads.confluent.io/api/plugins/confluentinc/kafka-connect-s3/versions/$S3_VERSION/confluentinc-kafka-connect-s3-$S3_VERSION.zip"
  rm -rf s3 && mkdir s3
  unzip -q -j -o ".download/confluentinc-kafka-connect-s3-$S3_VERSION.zip" "*/lib/*.jar" -d s3   # -j: flatten lib/ into s3/
  rm -rf .download
fi

ls -lh */
