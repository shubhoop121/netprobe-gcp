#!/bin/bash
set -e

echo "--- [validate-db.sh] Starting validation from within the Cloud SDK container ---"
sleep 60 # Wait for the log shipper to process the traffic

# The proxy is already in the container's PATH.
echo "--- [validate-db.sh] Starting Cloud SQL Proxy ---"
cloud-sql-proxy --ip-address-types=PRIVATE $DB_CONNECTION_NAME &
sleep 5 # Wait for proxy to initialize

# The psql client is also already in the container's PATH.
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