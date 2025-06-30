# Database Helper Scripts

A comprehensive collection of PostgreSQL database management scripts for backup, restore, user management, and database copying operations.

## Overview

This repository contains three powerful bash scripts designed to simplify PostgreSQL database operations:

- **`db-backup-restore`** - Advanced backup and restore functionality with enterprise-grade features
- **`db-user-manager`** - Comprehensive user and permission management system
- **`db-copy`** - Database copying/cloning with flexible options for schema, data, and filtering

All scripts are production-ready with extensive error handling, logging, security features, and support for complex database environments.

## Prerequisites

- **PostgreSQL Client Tools**: `psql`, `pg_dump`, `pg_restore`
- **Bash**: Version 4.0 or higher
- **System Tools**: `gzip`, `bzip2`, or `lz4` (for compression)
- **Permissions**: Appropriate database user privileges for the operations you want to perform

### Installation

1. Clone or download the scripts
2. Make them executable:
   ```bash
   chmod +x db-backup-restore db-user-manager db-copy
   ```
3. Optionally, add them to your PATH:
   ```bash
   sudo ln -s /path/to/db-backup-restore /usr/local/bin/
   sudo ln -s /path/to/db-user-manager /usr/local/bin/
   sudo ln -s /path/to/db-copy /usr/local/bin/
   ```

## Quick Start

### Database Backup & Restore

```bash
# Basic backup
./db-backup-restore backup -H localhost -U postgres -d myapp

# Backup with compression
./db-backup-restore backup -H localhost -U postgres -d myapp -c gzip

# Restore from backup
./db-backup-restore restore -f ./backups/myapp_backup.sql.gz --force

# List available backups
./db-backup-restore list -D ./backups
```

### Database Copy & Clone

```bash
# Copy database on same server
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy

# Copy database between servers
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging

# Copy schema only
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_schema --schema-only

# Copy with table filtering
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_filtered \
  --include-table users --include-table orders --exclude-table temp_*
```

### User Management

```bash
# Create a new user
./db-user-manager create-user -H localhost -U postgres -d myapp --new-user newuser --password

# Grant database access
./db-user-manager grant-db-access -H localhost -U postgres -d myapp --target-user newuser

# List all users and permissions
./db-user-manager list-users -H localhost -U postgres -d myapp

# Show user permissions
./db-user-manager show-user-permissions -H localhost -U postgres -d myapp --target-user newuser
```

## Common Tasks

### 1. Complete Database Backup

Create a comprehensive backup with extensions and compression:

```bash
# Full backup with all extensions
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --include-extensions \
  -c gzip \
  -D ./backups

# Schema-only backup
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --schema-only \
  -f plain
```

### 2. Database Copying/Cloning

Copy databases for development, testing, or migration purposes:

```bash
# Create development copy
./db-copy copy -H localhost -U postgres -d production_db --target-dbname dev_db

# Copy to staging server with data filtering
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging \
  --exclude-table audit_logs --exclude-table temp_*

# Copy schema for new environment setup
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_template \
  --schema-only --include-extensions

# Clone with validation and parallel processing
./db-copy copy -H localhost -U postgres -d large_db --target-dbname large_db_copy \
  --jobs 4 --validate --progress
```

### 3. Selective Backup

Backup specific tables or exclude temporary data:

```bash
# Backup specific tables only
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --include-table users \
  --include-table orders \
  --include-table products

# Exclude temporary/cache tables
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --exclude-table temp_* \
  --exclude-table cache_*
```

### 4. Restore Operations

```bash
# Restore with database recreation
./db-backup-restore restore \
  -f ./backups/myapp_20240101_120000.sql.gz \
  --force \
  -H localhost -U postgres

# Clean restore (drop existing objects first)
./db-backup-restore restore \
  -f ./backups/myapp_backup.sql \
  --clean \
  -H localhost -U postgres -d myapp
```

### 5. User Creation and Management

```bash
# Create user with password prompt
./db-user-manager create-user \
  -H localhost -U postgres -d myapp \
  --new-user appuser \
  --password

# Create user with specific permissions
./db-user-manager create-user \
  -H localhost -U postgres -d myapp \
  --new-user readonly \
  --password
./db-user-manager grant-db-access \
  -H localhost -U postgres -d myapp \
  --target-user readonly \
  --privileges SELECT

# Set connection limits
./db-user-manager set-connection-limit \
  -H localhost -U postgres \
  --target-user appuser \
  --limit 10
```

### 6. Permission Management

```bash
# Grant table access
./db-user-manager grant-table-access \
  -H localhost -U postgres -d myapp \
  --target-user appuser \
  --table users \
  --privileges SELECT,INSERT,UPDATE

# Grant schema access
./db-user-manager grant-schema-access \
  -H localhost -U postgres -d myapp \
  --target-user appuser \
  --schema public \
  --privileges USAGE

# Copy permissions between users
./db-user-manager copy-user-permissions \
  -H localhost -U postgres -d myapp \
  --source-user appuser \
  --target-user newuser
```

### 7. Security Operations

```bash
# Lock user account
./db-user-manager lock-user \
  -H localhost -U postgres \
  --target-user suspendeduser

# Unlock user account
./db-user-manager unlock-user \
  -H localhost -U postgres \
  --target-user suspendeduser

# Security scan
./db-user-manager security-scan \
  -H localhost -U postgres -d myapp

# Terminate user connections
./db-user-manager terminate-user-connections \
  -H localhost -U postgres \
  --target-user problemuser
```

## Advanced Features

### Database Copy Script Advanced Options

#### Copy Types and Modes
```bash
# Schema-only copy (structure without data)
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_schema \
  --schema-only --include-extensions

# Data-only copy (data without schema)
./db-copy copy -H localhost -U postgres -d myapp --target-dbname existing_db \
  --data-only

# Full copy with parallel processing
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy \
  --jobs 4 --progress
```

#### Table and Schema Filtering
```bash
# Copy specific tables only
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_partial \
  --include-table users \
  --include-table orders \
  --include-table products

# Exclude sensitive or temporary data
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_clean \
  --exclude-table audit_logs \
  --exclude-table temp_* \
  --exclude-table session_data

# Copy specific schemas
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_public \
  --include-schema public \
  --exclude-schema internal
```

#### Cross-Server Database Copying
```bash
# Copy from production to staging
./db-copy copy \
  --src-host prod.example.com --src-port 5432 --src-user app_user --src-dbname myapp \
  --target-host staging.example.com --target-port 5432 --target-user app_user --target-dbname myapp_staging \
  --password

# Copy with SSL connection
./db-copy copy \
  --src-host secure-db.example.com --src-user postgres --src-dbname myapp \
  --target-host local-dev.example.com --target-user postgres --target-dbname myapp_dev \
  --sslmode require --sslcert client.crt --sslkey client.key
```

#### Safety and Validation Features
```bash
# Replace existing database with confirmation
./db-copy copy -H localhost -U postgres -d myapp --target-dbname existing_db \
  --drop-target

# Skip confirmation for automated scripts
./db-copy copy -H localhost -U postgres -d myapp --target-dbname test_db \
  --drop-target --skip-confirmation

# Validate copy results
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy \
  --validate --verbose

# Dry run to see what would be copied
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy \
  --dry-run --verbose
```

#### Performance and Monitoring
```bash
# Parallel processing for large databases
./db-copy copy -H localhost -U postgres -d large_db --target-dbname large_db_copy \
  --jobs 8 --progress --progress-interval 10

# Copy with logging
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy \
  --log-file copy.log --verbose

# Copy excluding large objects for faster transfer
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy \
  --exclude-large-objects
```

### Backup Script Advanced Options

#### Performance Optimization
```bash
# Parallel backup with multiple jobs
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --jobs 4 \
  --parallel-tables

# Custom compression level
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  -c gzip \
  --compress-level 9
```

#### Monitoring and Logging
```bash
# Backup with progress monitoring
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --progress \
  --log-file backup.log \
  --metrics-file metrics.csv

# Webhook notifications
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --notify-webhook https://hooks.slack.com/your-webhook
```

#### Validation and Safety
```bash
# Backup with validation
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --validate-schema \
  --check-constraints \
  --backup-manifest

# Backup with retry logic
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --retry-count 5 \
  --retry-delay 10 \
  --retry-backoff
```

### User Management Advanced Options

#### Bulk Operations
```bash
# Create multiple users from file
./db-user-manager create-users-batch \
  -H localhost -U postgres -d myapp \
  --file users.txt

# Bulk grant permissions
./db-user-manager bulk-grant \
  -H localhost -U postgres -d myapp \
  --users user1,user2,user3 \
  --privileges SELECT,INSERT
```

#### Role Management
```bash
# Create role
./db-user-manager create-role \
  -H localhost -U postgres \
  --role-name app_readonly

# Assign role to user
./db-user-manager assign-role \
  -H localhost -U postgres \
  --target-user appuser \
  --role app_readonly

# List all roles
./db-user-manager list-roles \
  -H localhost -U postgres
```

#### Auditing and Compliance
```bash
# Generate comprehensive audit report
./db-user-manager audit-permissions \
  -H localhost -U postgres -d myapp \
  --output-file audit_report.txt

# Backup user permissions
./db-user-manager backup-permissions \
  -H localhost -U postgres -d myapp \
  --output-file permissions_backup.sql

# Restore user permissions
./db-user-manager restore-permissions \
  -H localhost -U postgres -d myapp \
  --input-file permissions_backup.sql
```

## Configuration Management

### Environment Variables

Both scripts support environment variables for connection settings:

```bash
# Set database connection
export DATABASE_URL="postgresql://user:password@localhost:5432/dbname"
export PGPASSWORD="your_password"

# SSL configuration
export PGSSLMODE="require"
export PGSSLCERT="/path/to/client-cert.pem"
export PGSSLKEY="/path/to/client-key.pem"
```

### Configuration Files

```bash
# Save current settings to config file
./db-backup-restore backup --save-config database.conf

# Load settings from config file
./db-backup-restore backup --config-file database.conf

# User manager config
./db-user-manager create-user --save-config user_mgmt.conf
./db-user-manager list-users --load-config user_mgmt.conf
```

## Error Handling and Troubleshooting

### Common Issues

1. **Connection Failures**
   ```bash
   # Test connection with timeout
   ./db-backup-restore backup --connection-timeout 10 -v
   ```

2. **Permission Errors**
   ```bash
   # Run with verbose output for debugging
   ./db-user-manager create-user -v --target-user newuser
   ```

3. **Disk Space Issues**
   ```bash
   # Skip disk space check if needed
   ./db-backup-restore backup --no-disk-check
   ```

### Logging and Monitoring

```bash
# Enable verbose logging
./db-backup-restore backup -v --log-file detailed.log

# Monitor with progress updates
./db-backup-restore backup --progress --progress-interval 30

# Send logs to syslog
./db-backup-restore backup --syslog
```

## Security Considerations

1. **Password Security**: Use `--passwd-stdin` or environment variables instead of command line parameters
2. **File Permissions**: Ensure backup files have appropriate permissions (600 or 640)
3. **SSL Connections**: Use SSL for production environments
4. **Audit Logging**: Enable logging for compliance requirements

## Common Workflows

### Development Environment Setup
```bash
# 1. Copy production database to staging
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging \
  --exclude-table audit_logs --exclude-table user_sessions

# 2. Create local development copy with only essential data
./db-copy copy -H staging.example.com -U postgres -d myapp_staging \
  --target-dbname myapp_dev --include-table users --include-table products

# 3. Set up development users
./db-user-manager create-user -H localhost -U postgres -d myapp_dev \
  --new-user dev_user --password
./db-user-manager grant-db-access -H localhost -U postgres -d myapp_dev \
  --target-user dev_user
```

### Database Migration Workflow
```bash
# 1. Create backup of source database
./db-backup-restore backup -H old-server.com -U postgres -d legacy_app \
  --include-extensions -c gzip -D ./migration-backups

# 2. Copy schema to new server
./db-copy copy \
  --src-host old-server.com --src-user postgres --src-dbname legacy_app \
  --target-host new-server.com --target-user postgres --target-dbname modern_app \
  --schema-only --include-extensions

# 3. Migrate data in batches (if needed)
./db-copy copy \
  --src-host old-server.com --src-user postgres --src-dbname legacy_app \
  --target-host new-server.com --target-user postgres --target-dbname modern_app \
  --data-only --include-table critical_data

# 4. Set up users on new server
./db-user-manager copy-user-permissions \
  -H old-server.com -U postgres -d legacy_app \
  --source-user app_user --target-user app_user \
  --target-host new-server.com --target-dbname modern_app
```

### Testing and QA Workflows
```bash
# 1. Create test database from latest production backup
./db-backup-restore restore -f ./backups/prod_latest.sql.gz \
  -H test-server.com -U postgres --target-dbname test_myapp --force

# 2. Alternatively, copy directly from production
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host test-server.com --target-user postgres --target-dbname test_myapp \
  --exclude-table sensitive_data --validate

# 3. Create test users with limited permissions
./db-user-manager create-user -H test-server.com -U postgres -d test_myapp \
  --new-user qa_user --password
./db-user-manager grant-table-access -H test-server.com -U postgres -d test_myapp \
  --target-user qa_user --table users --privileges SELECT
```

### Automated Backup and Copy Scheduling
```bash
#!/bin/bash
# daily-backup-and-copy.sh

# Create nightly backup
./db-backup-restore backup -H prod.example.com -U postgres -d myapp \
  --include-extensions -c gzip -D ./nightly-backups \
  --log-file backup-$(date +%Y%m%d).log

# Update staging database
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging \
  --drop-target --skip-confirmation \
  --exclude-table temp_* --exclude-table session_*

# Verify staging database
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging \
  --validate --dry-run
```

## Performance Tips

1. **Parallel Processing**: Use `--jobs` parameter for large databases
2. **Compression**: Choose appropriate compression based on CPU vs. storage trade-offs
3. **Selective Backups**: Use include/exclude options for large databases
4. **Selective Copying**: Use table/schema filtering to copy only necessary data
5. **Connection Pooling**: Configure connection limits appropriately
6. **Network Optimization**: Use SSL compression for cross-server copies

## Script Versions

- **db-backup-restore**: v2.0.0
- **db-user-manager**: v1.0.0
- **db-copy**: v1.0.0

## Support

For help with specific commands, use the built-in help system:

```bash
./db-backup-restore help
./db-backup-restore backup --help
./db-user-manager help
./db-user-manager create-user --help
./db-copy help
```

## Contributing

When modifying these scripts:
1. Maintain backward compatibility
2. Add appropriate error handling
3. Update help documentation
4. Test with various PostgreSQL versions
5. Follow security best practices
