#!/bin/sh
set -ex

echo "--- [DEBUG] STARTING DASHBOARD CONTAINER ---"

PORT="${PORT:-8080}"
API_URL="${API_SERVICE_URL:-http://api-not-configured}"

echo "--- [DEBUG] PORT = $PORT"
echo "--- [DEBUG] API_SERVICE_URL = $API_URL"

CONFIG_FILE="/etc/nginx/conf.d/default.conf"

echo "--- [DEBUG] Original nginx.conf: ---"
cat $CONFIG_FILE
echo "----------------------------------------"

sed -i "s|__PORT__|$PORT|g" $CONFIG_FILE
sed -i "s|__API_SERVICE_URL__|${API_URL}|g" $CONFIG_FILE

echo "--- [DEBUG] FINAL NGINX CONFIG (after sed): ---"
cat $CONFIG_FILE
echo "----------------------------------------"

echo "--- [DEBUG] Starting Nginx... ---"
nginx -g 'daemon off;'minor fix 114