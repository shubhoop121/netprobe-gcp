set -e

DB_CONNECTION_NAME=$1

if [ -z "$DB_CONNECTION_NAME" ]; then
  echo "Error: Database connection name was not provided as an argument."
  exit 1
fi

echo "--- [create-schema.sh] Applying schema to instance: $DB_CONNECTION_NAME ---"

echo "--- [create-schema.sh] Installing PostgreSQL client ---"
apt-get update && apt-get install -y postgresql-client

echo "--- [create-schema.sh] Starting Cloud SQL Proxy ---"
cloud-sql-proxy --ip-address-types=PRIVATE $DB_CONNECTION_NAME &
sleep 5

echo "Waiting for proxy to accept connections on localhost..."
for i in {1..10}; do
  if pg_isready -h 127.0.0.1 -U netprobe_user -d netprobe_logs; then
    echo "Proxy is ready and connected."
    break
  fi
  echo "Attempt $i/10 failed. Waiting 15 seconds..."
  sleep 15
done

if ! pg_isready -h 127.0.0.1 -U netprobe_user -d netprobe_logs; then
  echo "Cloud SQL Proxy did not become ready after 2.5 minutes."
  echo "--- Attempting to find proxy logs (might be empty) ---"
  find / -name cloud-sql-proxy.log -exec cat {} \; 2>/dev/null || echo "No proxy log file found."
  exit 1
fi

echo "--- Proxy is ready. Applying schema. ---"
psql --host=127.0.0.1 --username=netprobe_user --dbname=netprobe_logs <<-EOF
  CREATE TABLE connections ( id SERIAL PRIMARY KEY, ts TIMESTAMP WITH TIME ZONE NOT NULL, uid VARCHAR(255) UNIQUE NOT NULL, source_ip INET NOT NULL, source_port INTEGER NOT NULL, destination_ip INET NOT NULL, destination_port INTEGER NOT NULL, proto VARCHAR(6), service VARCHAR(255), duration FLOAT, orig_bytes BIGINT, resp_bytes BIGINT, conn_state VARCHAR(10), logged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() );
EOF
echo "--- Schema applied successfully via proxy ---"