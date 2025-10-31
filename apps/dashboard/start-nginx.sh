#!/bin/sh
# This script is run when the container starts

# Read the PORT environment variable (default to 8080)
PORT="${PORT:-8080}"

# Read the API_SERVICE_URL, default to a placeholder if not set
# (Note: The |g acts as a delimiter for sed)
API_URL="${API_SERVICE_URL:-http://api-not-configured}"
sed -i "s|__PORT__|$PORT|g" /etc/nginx/conf.d/default.conf
sed -i "s|__API_SERVICE_URL__|$API_URL/|g" /etc/nginx/conf.d/default.conf

# Start Nginx
echo "Starting Nginx on port $PORT..."
echo "Proxying /api/ to $API_URL/"
nginx -g 'daemon off;'