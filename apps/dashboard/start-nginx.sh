#!/bin/sh
set -ex

echo "--- [DEBUG] STARTING DASHBOARD CONTAINER ---"

PORT="${PORT:-8080}"
echo "--- [DEBUG] PORT = $PORT"

CONFIG_FILE="/etc/nginx/conf.d/default.conf"

echo "--- [DEBUG] Original nginx.conf: ---"
cat $CONFIG_FILE
echo "----------------------------------------"

# Only replace the PORT placeholder
sed -i "s|__PORT__|$PORT|g" $CONFIG_FILE

echo "--- [DEBUG] FINAL NGINX CONFIG (after sed): ---"
cat $CONFIG_FILE
echo "----------------------------------------"

echo "--- [DEBUG] Starting Nginx... ---"
nginx -g 'daemon off;'