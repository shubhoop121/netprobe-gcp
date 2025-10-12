#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "--- [create-schema.sh] Applying database schema with retry loop ---"

# This script will be run inside the google/cloud-sdk container,
# so all necessary tools (gcloud, psql, cloud-sql-proxy) are already installed.
# The DB_IP and PGPASSWORD will be passed in as environment variables from the workflow.

# Retry loop to wait for the database to become available
echo "Waiting for database instance to accept connections..."
for i in {1..10}; do
  if pg_isready -h $DB_IP -U netprobe_user -d netprobe_logs; then
    echo "Database is ready."
    break
  fi
  echo "Attempt $i/10 failed. Waiting 30 seconds..."
  sleep 30
done

# Final check after the loop
if ! pg_isready -h $DB_IP -U netprobe_user -d netprobe_logs; then
  echo "Database did not become ready after 5 minutes."
  exit 1
fi

# Now that we know it's ready, run the CREATE TABLE command
echo "--- Database is ready. Applying schema. ---"
psql --host=$DB_IP --username=netprobe_user --dbname=netprobe_logs <<-EOF
  CREATE TABLE connections (
      id SERIAL PRIMARY KEY,
      ts TIMESTAMP WITH TIME ZONE NOT NULL,
      uid VARCHAR(255) UNIQUE NOT NULL,
      source_ip INET NOT NULL,
      source_port INTEGER NOT NULL,
      destination_ip INET NOT NULL,
      destination_port INTEGER NOT NULL,
      proto VARCHAR(6),
      service VARCHAR(255),
      duration FLOAT,
      orig_bytes BIGINT,
      resp_bytes BIGINT,
      conn_state VARCHAR(10),
      logged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
  );
EOF
echo "--- Schema applied successfully ---"