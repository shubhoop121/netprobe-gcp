# --- Build Stage ---
FROM node:20-alpine AS build

WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn build

# --- Serve Stage ---
FROM nginx:1.25-alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY start-nginx.sh /start-nginx.sh
RUN chmod +x /start-nginx.sh
CMD ["/start-nginx.sh"]
