# apps/dashboard/Dockerfile (Final Version)

# --- Build Stage ---
# Use Node 20
FROM node:20-alpine AS build

WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .
RUN yarn build

# --- Serve Stage ---
FROM nginx:1.25-alpine

# Copy the static build files
COPY --from=build /app/dist /usr/share/nginx/html

# Copy the Nginx config that has the new resolver logic
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the startup script (which now only sets the PORT)
COPY start-nginx.sh /start-nginx.sh
RUN chmod +x /start-nginx.sh

# Expose 80 (Nginx default, but good practice)
EXPOSE 80

# Run the startup script
CMD ["/start-nginx.sh"]