#!/bin/sh
# Add -x to print every command that runs
set -ex

# Read env vars provided by Cloud Run
PORT="${PORT:-8080}"
API_URL="${API_SERVICE_URL:-http://api-not-setcom}"

echo "--- DEBUG: SCRIPT STARTED ---"
echo "--- DEBUG: PORT = $PORT"
echo "--- DEBUG: API_SERVICE_URL = $API_URL"
echo "--- DEBUG: Original nginx.conf: ---"
cat /etc/nginx/conf.d/default.conf
echo "--- DEBUG: Running sed commands... ---"

# Replace the placeholders
sed -i "s|__PORT__|$PORT|g" /etc/nginx/conf.d/default.conf
sed -i "s|__API_SERVICE_URL__|$API_URL|g" /etc/nginx/conf.d/default.conf

# --- THIS IS THE MOST IMPORTANT STEP ---
# Print the final config file *after* sed has modified it.
echo "--- DEBUG: FINAL NGINX CONFIG: ---"
cat /etc/nginx/conf.d/default.conf
echo "--- DEBUG: Starting Nginx... ---"

# Start Nginx
nginx -g 'daemon off;'