# --- 1. Build Stage ---
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn config set network-timeout 600000 -g && \
    yarn config set registry https://registry.npmjs.org && \
    yarn install --frozen-lockfile

COPY . .
RUN yarn build
# Result in /app/dist

# --- 2. Serve Stage ---
FROM node:20-alpine
WORKDIR /app

COPY package.json yarn.lock ./

# Retry logic + npm mirror to avoid transient 500s
RUN yarn config set network-timeout 600000 -g && \
    yarn config set registry https://registry.npmjs.org && \
    for i in 1 2 3; do yarn install --production && break || sleep 5; done

COPY server.js .
COPY --from=build /app/dist ./dist

EXPOSE ${PORT:-8080}
CMD ["node", "server.js"]
