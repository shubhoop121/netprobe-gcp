# --- 1. Build Stage ---
# This stage builds the React app
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn build
# The result is in /app/dist

# --- 2. Serve Stage ---
# This stage creates a slim, secure production server
FROM node:20-alpine
WORKDIR /app

# Copy only the files needed for the Node.js server
COPY package.json yarn.lock ./

RUN yarn install --production

COPY server.js .

# Copy the built React app from the 'build' stage
COPY --from=build /app/dist ./dist

# Expose the port Cloud Run provides
EXPOSE ${PORT:-8080}

# The command to run our server
CMD ["node", "server.js"]