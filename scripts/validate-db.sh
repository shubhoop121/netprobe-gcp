#!/bin/bash
# Exit on error, treat unset variables as errors, propagate exit codes
set -euo pipefail
trap 'echo "[ERROR] Validation failed at line $LINENO"; exit 1' ERR

DB_INSTANCE_NAME="netprobe-db"

echo "--- [validate-db.sh] Starting validation for instance: $DB_INSTANCE_NAME ---"
sleep 60 # Wait for shipper

echo "--- [validate-db.sh] Installing PostgreSQL client & Downloading Proxy ---"
apt-get update && apt-get install -y postgresql-client curl
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.0/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy
./cloud-sql-proxy --version

echo "--- [validate-db.sh] Starting Cloud SQL Proxy ---"
./cloud-sql-proxy --private-ip $DB_INSTANCE_NAME &
PROXY_PID=$!
sleep 5

echo "--- [validate-db.sh] Fetching database password ---"
DB_PASS=$(gcloud secrets versions access latest --secret="db-password")
export PGPASSWORD=$DB_PASS

echo "--- [validate-db.sh] Querying database ---"
RESULT=$(psql --host=127.0.0.1 --username=netprobe_user --dbname=netprobe_logs -t -c "SELECT COUNT(*) FROM connections;")
COUNT=$(echo $RESULT | xargs)

echo "Found $COUNT records in the connections table."
if (( COUNT > 0 )); then
  echo "✅ Validation successful."
else
  echo "Validation failed."
  exit 1
fi

echo "--- Shutting down background proxy (PID $PROXY_PID) ---"
kill $PROXY_PID