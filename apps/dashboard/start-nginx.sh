#!/bin/sh
# This script is run when the container starts

# Read the PORT environment variable provided by Cloud Run, default to 8080
PORT="${PORT:-8080}"

# Find the placeholder __PORT__ in the config file and replace it with the actual port
sed -i "s/__PORT__/$PORT/g" /etc/nginx/conf.d/default.conf

# Start Nginx in the foreground (which is required by Cloud Run)
echo "Starting Nginx on port $PORT..."
nginx -g 'daemon off;'