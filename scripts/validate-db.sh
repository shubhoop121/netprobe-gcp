#!/bin/bash
set -e

# Read the connection name from the first command-line argument
DB_CONNECTION_NAME=$1

echo "--- [validate-db.sh] Starting validation for instance: $DB_CONNECTION_NAME ---"
sleep 60

# Start the proxy
echo "--- [validate-db.sh] Starting Cloud SQL Proxy ---"
cloud-sql-proxy --ip-address-types=PRIVATE $DB_CONNECTION_NAME &
sleep 5

# Install the PostgreSQL client before trying to use it.
echo "--- [validate-db.sh] Installing PostgreSQL client ---"
apt-get update && apt-get install -y postgresql-client
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.0/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy

# The gcloud CLI is also pre-authenticated.
echo "--- [validate-db.sh] Fetching database password ---"
DB_PASS=$(gcloud secrets versions access latest --secret="db-password")
export PGPASSWORD=$DB_PASS

# Query the database for records
echo "--- [validate-db.sh] Querying database ---"
RESULT=$(psql --host=127.0.0.1 --username=netprobe_user --dbname=netprobe_logs -t -c "SELECT COUNT(*) FROM connections;")
COUNT=$(echo $RESULT | xargs)

echo "Found $COUNT records in the connections table."
if (( COUNT > 0 )); then
  echo "Validation successful: Log data was found in the database."
  exit 0
else
  echo "Validation failed: No log data was found in the database."
  exit 1
fi