FROM ubuntu:24.04

LABEL maintainer="hongkongkiwi"
LABEL description="Database helper scripts for PostgreSQL backup, restore, copy, and user management"
LABEL version="2.0.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/local/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    curl \
    wget \
    gzip \
    bzip2 \
    lz4 \
    xz-utils \
    ca-certificates \
    bash \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy scripts and supporting files
COPY db-backup-restore /usr/local/bin/
COPY db-copy /usr/local/bin/
COPY db-user-manager /usr/local/bin/
COPY run-tests /usr/local/bin/
COPY Taskfile.yml ./
COPY README.md ./

# Copy tests directory for validation
COPY tests/ ./tests/

# Make scripts executable
RUN chmod +x /usr/local/bin/db-backup-restore \
    /usr/local/bin/db-copy \
    /usr/local/bin/db-user-manager \
    /usr/local/bin/run-tests

# Install Task (if available)
RUN curl -sL https://taskfile.dev/install.sh | sh -s -- -b /usr/local/bin v3.37.2 || true

# Create directory for backups and logs
RUN mkdir -p /data/backups /data/logs

# Set up environment
ENV DB_BACKUP_DIR="/data/backups"
ENV LOG_DIR="/data/logs"

# Health check to verify scripts are working
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD db-backup-restore --version || exit 1

# Default command shows help
CMD ["db-backup-restore", "help"]
