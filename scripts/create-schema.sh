#!/bin/bash
set -e

DB_INSTANCE_NAME="netprobe-db"

echo "--- [create-schema.sh] Applying schema to instance: $DB_INSTANCE_NAME ---"

echo "--- [create-schema.sh] Installing PostgreSQL client ---"
apt-get update && apt-get install -y postgresql-client
echo "--- [create-schema.sh] Connecting via gcloud and applying schema ---"
gcloud sql connect $DB_INSTANCE_NAME --user=netprobe_user <<-EOF
  CREATE TABLE connections ( id SERIAL PRIMARY KEY, ts TIMESTAMP WITH TIME ZONE NOT NULL, uid VARCHAR(255) UNIQUE NOT NULL, source_ip INET NOT NULL, source_port INTEGER NOT NULL, destination_ip INET NOT NULL, destination_port INTEGER NOT NULL, proto VARCHAR(6), service VARCHAR(255), duration FLOAT, orig_bytes BIGINT, resp_bytes BIGINT, conn_state VARCHAR(10), logged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() );
EOF
echo "--- Schema applied successfully ---"
D