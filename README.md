# Database Helper Scripts

A collection of production-ready PostgreSQL database management scripts for backup, restore, user management, and database copying operations.

## Overview

This repository contains three powerful bash scripts:

- **`db-backup-restore`** - Backup and restore functionality with compression, filtering, and validation
- **`db-user-manager`** - User and permission management system
- **`db-copy`** - Database copying/cloning with schema/data filtering and cross-server support

All scripts include comprehensive error handling, logging, security validation, and support for complex database environments.

## Prerequisites

- **PostgreSQL Client Tools**: `psql`, `pg_dump`, `pg_restore`, `createdb`, `dropdb`
- **Bash**: Version 4.0 or higher
- **System Tools**: `gzip`, `bzip2`, or `lz4` (for compression)
- **Permissions**: Appropriate database user privileges

### Platform Compatibility

These scripts are designed to work seamlessly on both **macOS** and **Linux**:

- **macOS**: Uses BSD variants of system utilities by default, with automatic fallback to GNU versions if installed via Homebrew (e.g., `gstat`, `gtimeout`)
- **Linux**: Uses GNU variants of system utilities natively
- **Cross-platform features**: Automatic detection and handling of platform differences for commands like `stat`, `timeout`, `date`, and `sed`

For optimal compatibility on macOS, consider installing GNU utilities:
```bash
# macOS: Install GNU utilities for enhanced compatibility
brew install coreutils findutils gnu-sed
```

The scripts will automatically detect and use the appropriate command variants for your platform.

## Installation

### Quick Installation (Recommended)

Each script includes built-in installation commands for easy setup:

```bash
# Install to ~/.local/bin (user-specific, no sudo required)
./db-backup-restore install
./db-copy install
./db-user-manager install

# Make sure ~/.local/bin is in your PATH
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd db-helper-scripts
   ```

2. Make scripts executable:
   ```bash
   chmod +x db-backup-restore db-user-manager db-copy
   ```

3. Optionally add to PATH:
   ```bash
   sudo ln -s $PWD/db-backup-restore /usr/local/bin/
   sudo ln -s $PWD/db-user-manager /usr/local/bin/
   sudo ln -s $PWD/db-copy /usr/local/bin/
   ```

### Using Task (Taskfile.yml)

If you have [Task](https://taskfile.dev/) installed, you can use our Taskfile for common operations:

```bash
# Install Task first
brew install go-task/tap/go-task  # macOS
# or
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d  # Linux

# Common tasks
task install           # Install all scripts to ~/.local/bin
task uninstall         # Remove scripts from ~/.local/bin
task update            # Update scripts to latest GitHub release
task dev:test          # Run all tests
task dev:test:fast     # Run fast tests only
task dev:clean         # Clean up test artifacts
task check:deps        # Check system dependencies
```

## Development Setup

### Pre-commit Hooks

This project uses pre-commit hooks to maintain code quality:

```bash
# Install pre-commit
pip install pre-commit

# Install the hooks for this repo
pre-commit install

# That's it! Hooks will run automatically on each commit
```

The hooks will automatically check shell script quality, fix formatting, and validate permissions before each commit.

## Quick Start

### Script Management

Each script includes built-in management commands:

```bash
# Install script globally
./db-backup-restore install

# Update to latest version
./db-backup-restore update

# Remove from system
./db-backup-restore uninstall

# Check version
./db-backup-restore version
```

### Backup & Restore

```bash
# Create backup
./db-backup-restore backup -H localhost -U postgres -d myapp

# Restore backup
./db-backup-restore restore -f backup.sql.gz --force

# List backups
./db-backup-restore list -D ./backups
```

### Database Copy

```bash
# Copy database locally
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_copy

# Copy between servers
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging

# Copy schema only
./db-copy copy -H localhost -U postgres -d myapp --target-dbname myapp_schema --schema-only
```

### User Management

```bash
# Create user
./db-user-manager create-user -H localhost -U postgres -d myapp --new-user newuser --password

# Grant database access
./db-user-manager grant-db-access -H localhost -U postgres -d myapp --target-user newuser

# List users
./db-user-manager list-users -H localhost -U postgres -d myapp
```

## Common Tasks

### Production Backup
```bash
# Full backup with compression and validation
./db-backup-restore backup \
  -H localhost -U postgres -d myapp \
  --include-extensions -c gzip \
  --validate-schema --backup-manifest
```

### Development Environment Setup
```bash
# 1. Copy production to staging (excluding sensitive data)
./db-copy copy \
  --src-host prod.example.com --src-user postgres --src-dbname myapp \
  --target-host staging.example.com --target-user postgres --target-dbname myapp_staging \
  --exclude-table audit_logs --exclude-table user_sessions

# 2. Create local development copy
./db-copy copy -H staging.example.com -U postgres -d myapp_staging \
  --target-dbname myapp_dev --include-table users --include-table products

# 3. Set up development user
./db-user-manager create-user -H localhost -U postgres -d myapp_dev \
  --new-user dev_user --password
```

### Database Migration
```bash
# 1. Backup source database
./db-backup-restore backup -H old-server.com -U postgres -d legacy_app \
  --include-extensions -c gzip

# 2. Copy schema to new server
./db-copy copy \
  --src-host old-server.com --src-user postgres --src-dbname legacy_app \
  --target-host new-server.com --target-user postgres --target-dbname modern_app \
  --schema-only --include-extensions

# 3. Migrate data
./db-copy copy \
  --src-host old-server.com --src-user postgres --src-dbname legacy_app \
  --target-host new-server.com --target-user postgres --target-dbname modern_app \
  --data-only
```

## Advanced Features

### Backup & Restore Options
- **Compression**: gzip, bzip2, lz4 with custom levels
- **Filtering**: Include/exclude tables, schemas, or data
- **Parallel processing**: Multi-job backup/restore
- **Validation**: Schema validation and constraint checking
- **Monitoring**: Progress tracking, metrics, and webhook notifications

### Database Copy Features
- **Flexible copying**: Schema-only, data-only, or full copy
- **Cross-server support**: Copy between different PostgreSQL servers
- **Table filtering**: Include/exclude specific tables or patterns
- **Safety checks**: Prevents copying database to itself
- **Validation**: Verify copy integrity and performance

### User Management Features
- **User lifecycle**: Create, modify, lock, unlock, delete users
- **Permission management**: Grant/revoke table, schema, and database permissions
- **Role management**: Create and assign roles
- **Security**: Reserved user prevention, permission auditing
- **Bulk operations**: Batch user creation and permission management

## Configuration

### Environment Variables
```bash
export DATABASE_URL="postgresql://user:password@localhost:5432/dbname"
export PGPASSWORD="your_password"
export PGSSLMODE="require"
```

### Configuration Files
```bash
# Save/load configuration
./db-backup-restore backup --save-config database.conf
./db-backup-restore backup --config-file database.conf
```

## Testing

This repository includes a comprehensive test suite using Docker and bats (Bash Automated Testing System). The test suite provides:

- **Isolated testing environment** with Docker PostgreSQL containers
- **Comprehensive coverage** of all script features and edge cases
- **Performance testing** and validation
- **Cross-server testing** with multiple database instances
- **Automated setup** and teardown

### Running Tests

#### Option 1: Local Testing (Install Dependencies)
```bash
# Setup test environment (installs bats and dependencies)
cd tests && ./setup-tests.sh

# Run all tests
./run-tests

# Run with options
./run-tests --parallel 4 --verbose
./run-tests --test cross_platform
```

#### Option 2: Docker Testing (No Local Dependencies)
```bash
# Run tests in Docker container (no setup required)
./run-tests --docker

# Run specific tests in Docker
./run-tests --docker --test backup --verbose

# Or use docker-compose for full control
docker-compose -f docker-compose.test-runner.yml run test-runner ./run-tests
```

#### Platform-Specific Setup
- **macOS**: Uses Homebrew for dependencies (brew install bats-core coreutils)
- **Linux**: Uses package managers (apt, yum, dnf) for dependencies
- **Both**: Automatic detection of GNU vs BSD utilities for compatibility

#### Test Database Ports
Tests use non-standard ports to avoid conflicts with existing PostgreSQL instances:
- **Primary test database**: port 15432
- **Secondary test database**: port 15433

For detailed testing documentation, see [tests/README.md](tests/README.md).

## Updating and Maintenance

### Automatic Updates

Each script can update itself to the latest GitHub release:

```bash
# Check for and install updates
db-backup-restore update
db-copy update
db-user-manager update

# Or use Task to update all scripts
task update
```

### Version Management

```bash
# Check current versions
task release:version

# Check if scripts are up to date
db-backup-restore version
db-copy version
db-user-manager version
```

### Maintenance Tasks

Using the included Taskfile.yml:

```bash
# Development setup
task dev:setup

# Run linting on all scripts
task dev:lint

# Run comprehensive tests
task dev:test

# Clean up artifacts
task dev:clean

# Check system dependencies
task check:deps

# Check platform compatibility
task check:platform

# Run performance benchmarks
task benchmark
```

## Error Handling

### Common Issues

1. **Connection Failures**
   ```bash
   ./db-backup-restore backup --connection-timeout 10 -v
   ```

2. **Permission Errors**
   ```bash
   ./db-user-manager create-user -v --target-user newuser
   ```

3. **Disk Space Issues**
   ```bash
   ./db-backup-restore backup --no-disk-check
   ```

### Debugging
```bash
# Enable verbose logging
./db-backup-restore backup -v --log-file detailed.log

# Monitor progress
./db-backup-restore backup --progress --progress-interval 30
```

## Security

1. **Password Security**: Use `--passwd-stdin` or environment variables
2. **File Permissions**: Ensure backup files have appropriate permissions (600/640)
3. **SSL Connections**: Use SSL for production environments
4. **Reserved Users**: Scripts prevent creation of PostgreSQL reserved users
5. **Audit Logging**: Enable logging for compliance requirements

## Performance Tips

1. **Parallel Processing**: Use `--jobs` parameter for large databases
2. **Compression**: Balance CPU vs. storage based on your needs
3. **Selective Operations**: Use include/exclude options for large databases
4. **Connection Limits**: Configure appropriate connection limits
5. **Network Optimization**: Use SSL compression for cross-server operations

## Script Versions

- **db-backup-restore**: v2.0.0
- **db-user-manager**: v1.0.0
- **db-copy**: v1.0.0

## Help

Each script includes comprehensive help:

```bash
./db-backup-restore help
./db-backup-restore backup --help
./db-user-manager help
./db-copy help
```

## Contributing

When contributing:
1. Maintain backward compatibility
2. Add appropriate error handling and validation
3. Update help documentation
4. Add tests for new features
5. Follow security best practices

For adding tests, see the [testing documentation](tests/README.md).

## License

[Add your license here]
