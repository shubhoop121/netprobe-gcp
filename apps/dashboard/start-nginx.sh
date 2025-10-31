#!/bin/sh
set -e

# Read env vars provided by Cloud Run
PORT="${PORT:-8080}"
API_URL="${API_SERVICE_URL:-http://api-not-set.com}"

# Replace the placeholders in the config file
sed -i "s|__PORT__|$PORT|g" /etc/nginx/conf.d/default.conf
sed -i "s|__API_SERVICE_URL__|$API_URL|g" /etc/nginx/conf.d/default.conf

echo "Starting Nginx on port $PORT..."
echo "Proxying /api/ to $API_URL/"
nginx -g 'daemon off;'