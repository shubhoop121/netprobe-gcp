set -e

DB_CONNECTION_NAME=$1
if [ -z "$DB_CONNECTION_NAME" ]; then
  echo "Error: Database connection name was not provided."
  exit 1
fi

echo "--- [create-schema.sh] Installing dependencies ---"
apt-get update && apt-get install -y postgresql-client curl
curl -o cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.0/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy
./cloud-sql-proxy --version

echo "--- [create-schema.sh] Attempting brief foreground proxy connection... ---"
timeout 15s ./cloud-sql-proxy --private-ip $DB_CONNECTION_NAME || echo "Foreground proxy test timed out or failed (expected during schema creation)."
echo "--- [create-schema.sh] Foreground test complete. Proceeding with background proxy. ---"

echo "--- [create-schema.sh] Starting Cloud SQL Proxy in background ---"
./cloud-sql-proxy --private-ip $DB_CONNECTION_NAME &
PROXY_PID=$!
sleep 5

echo "Waiting for proxy (PID $PROXY_PID) to accept connections on localhost..."
for i in {1..10}; do
  if pg_isready -h 127.0.0.1 -U netprobe_user -d netprobe_logs; then
    echo "Proxy is ready and connected."
    break
  fi
  if ! ps -p $PROXY_PID > /dev/null; then
     echo "Background proxy process (PID $PROXY_PID) died unexpectedly!"
     find / -name cloud-sql-proxy.log -exec cat {} \; 2>/dev/null || echo "No proxy log file found."
     exit 1
  fi
  echo "Attempt $i/10 failed. Waiting 15 seconds..."
  sleep 15
done

if ! pg_isready -h 127.0.0.1 -U netprobe_user -d netprobe_logs; then
  echo "Cloud SQL Proxy did not become ready after 2.5 minutes."
  kill $PROXY_PID 2>/dev/null || true
  exit 1
fi

echo "--- Proxy is ready. Applying schema. ---"
psql --host=127.0.0.1 --username=netprobe_user --dbname=netprobe_logs <<-EOF
  CREATE TABLE connections ( id SERIAL PRIMARY KEY, ts TIMESTAMP WITH TIME ZONE NOT NULL, uid VARCHAR(255) UNIQUE NOT NULL, source_ip INET NOT NULL, source_port INTEGER NOT NULL, destination_ip INET NOT NULL, destination_port INTEGER NOT NULL, proto VARCHAR(6), service VARCHAR(255), duration FLOAT, orig_bytes BIGINT, resp_bytes BIGINT, conn_state VARCHAR(10), logged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() );
EOF
echo "--- Schema applied successfully ---"

echo "--- Shutting down background proxy (PID $PROXY_PID) ---"
kill $PROXY_PID