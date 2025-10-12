#!/bin/bash
set -e

# Read the database IP from the first command-line argument
DB_IP=$1

echo "--- [create-schema.sh] Applying schema to database at host: $DB_IP ---"

# Install the PostgreSQL client
echo "--- [create-schema.sh] Installing PostgreSQL client ---"
apt-get update && apt-get install -y postgresql-client

# Retry loop to wait for the database
echo "Waiting for database instance to accept connections..."
for i in {1..10}; do
  if pg_isready -h $DB_IP -U netprobe_user -d netprobe_logs; then
    echo "Database is ready."
    break
  fi
  echo "Attempt $i/10 failed. Waiting 30 seconds..."
  sleep 30
done

if ! pg_isready -h $DB_IP -U netprobe_user -d netprobe_logs; then
  echo "Database at $DB_IP did not become ready after 5 minutes."
  exit 1
fi

# Apply the schema
echo "--- Database is ready. Applying schema. ---"
psql --host=$DB_IP --username=netprobe_user --dbname=netprobe_logs <<-EOF
  CREATE TABLE connections ( id SERIAL PRIMARY KEY, ts TIMESTAMP WITH TIME ZONE NOT NULL, uid VARCHAR(255) UNIQUE NOT NULL, source_ip INET NOT NULL, source_port INTEGER NOT NULL, destination_ip INET NOT NULL, destination_port INTEGER NOT NULL, proto VARCHAR(6), service VARCHAR(255), duration FLOAT, orig_bytes BIGINT, resp_bytes BIGINT, conn_state VARCHAR(10), logged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() );
EOF
echo "--- Schema applied successfully to $DB_IP ---"