#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- [validate-db.sh] Validating that logs were shipped to the database ---"
sleep 60 # Wait for the log shipper to process the traffic

# Install and run the Cloud SQL Auth Proxy
echo "--- [validate-db.sh] Starting Cloud SQL Proxy ---"
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.0/cloud-sql-proxy.linux.amd64 && chmod +x cloud-sql-proxy
./cloud-sql-proxy --ip-address-types=PRIVATE $DB_CONNECTION_NAME &
sleep 5 # Wait for proxy to initialize

# Install psql client
echo "--- [validate-db.sh] Installing psql client ---"
sudo apt-get update && sudo apt-get install -y postgresql-client

# Get the password from Secret Manager
echo "--- [validate-db.sh] Fetching database password ---"
DB_PASS=$(gcloud secrets versions access latest --secret="db-password")
export PGPASSWORD=$DB_PASS

# Query the database for records
echo "--- [validate-db.sh] Querying database ---"
RESULT=$(psql --host=127.0.0.1 --username=netprobe_user --dbname=netprobe_logs -t -c "SELECT COUNT(*) FROM connections;")
COUNT=$(echo $RESULT | xargs)

echo "Found $COUNT records in the connections table."
if (( COUNT > 0 )); then
  echo "✅ Validation successful: Log data was found in the database."
  exit 0
else
  echo "❌ Validation failed: No log data was found in the database."
  exit 1
fi