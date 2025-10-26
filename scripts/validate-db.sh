#!/bin/bash
set -e

DB_INSTANCE_NAME="netprobe-db"

echo "--- [validate-db.sh] Starting validation for instance: $DB_INSTANCE_NAME ---"
sleep 60

echo "--- [validate-db.sh] Installing PostgreSQL client ---"
apt-get update && apt-get install -y postgresql-client

echo "--- [validate-db.sh] Fetching database password ---"
DB_PASS=$(gcloud secrets versions access latest --secret="db-password")
export PGPASSWORD=$DB_PASS

echo "--- [validate-db.sh] Connecting via gcloud and querying database ---"
echo "--- DEBUG: Checking PGPASSWORD environment variable ---"
echo "PGPASSWORD=[$PGPASSWORD]"
RESULT=$(gcloud alpha sql connect $DB_INSTANCE_NAME --user=netprobe_user --quiet --private-ip --verbosity=debug -- <<EOF
  SELECT COUNT(*) FROM connections;
EOF
)

COUNT=$(echo $RESULT | xargs)

echo "Found $COUNT records in the connections table."
if (( COUNT > 0 )); then
  echo "Validation successful."
  exit 0
else
  echo "Validation failed."
  exit 1
fi