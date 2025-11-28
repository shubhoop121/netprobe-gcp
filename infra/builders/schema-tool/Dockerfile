# Use the official Google Cloud SDK as the base (includes gcloud)
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:slim

RUN apt-get update && apt-get install -y postgresql-client procps && \
    rm -rf /var/lib/apt/lists/*

# We download it once during build time, so we never download it at runtime again.
RUN curl -o /usr/local/bin/cloud-sql-proxy https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.0/cloud-sql-proxy.linux.amd64 && \
    chmod +x /usr/local/bin/cloud-sql-proxy

# Set working directory
WORKDIR /workspace