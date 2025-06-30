#!/usr/bin/env bats

# Load test helpers and bats libraries
load '../helpers/test_helpers'
load '../bats-helpers/bats-support/load'
load '../bats-helpers/bats-assert/load'
load '../bats-helpers/bats-file/load'

# Setup and teardown
setup() {
    setup_test_environment

    # Ensure test databases exist and are clean
    cleanup_test_databases

    # Reset test data in primary database (use the working version)
    reset_test_data "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" || true
}

teardown() {
    cleanup_test_databases

    # Clean up backup files
    rm -f "${TEST_BACKUP_DIR}"/*
}

# Helper function to run db-backup-restore command
run_backup_restore_cmd() {
    # Use absolute path to the script
    if [[ -f "/workspace/db-backup-restore" ]]; then
        run /workspace/db-backup-restore "$@"
    else
        run ../db-backup-restore "$@"  # Fallback for local execution
    fi
}

# Test basic help and version commands
@test "db-backup-restore: help command shows usage information" {
    run_backup_restore_cmd help
    assert_success
    assert_output --partial "PostgreSQL Database Backup and Restore Tool"
    assert_output --partial "USAGE:"
    assert_output --partial "COMMANDS:"
    assert_output --partial "backup"
    assert_output --partial "restore"
}

@test "db-backup-restore: version command shows version information" {
    run_backup_restore_cmd version
    assert_success
    assert_output --partial "db-backup-restore version"
    assert_output --partial "v2.0.0"
}

@test "db-backup-restore: backup --help shows backup command help" {
    run_backup_restore_cmd backup --help
    assert_success
    assert_output --partial "Create database backup"
    assert_output --partial "Options:"
    assert_output --partial "--host"
    assert_output --partial "--dbname"
}

@test "db-backup-restore: restore --help shows restore command help" {
    run_backup_restore_cmd restore --help
    assert_success
    assert_output --partial "Restore database"
    assert_output --partial "Options:"
    assert_output --partial "--file"
}

# Test basic backup functionality
@test "db-backup-restore: basic database backup" {
    local backup_file="${TEST_BACKUP_DIR}/test_backup.sql"

    # Create backup directory
    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup command
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    assert_success
    assert_file_exists "$backup_file"

    # Verify backup file contains expected content
    assert file_contains "$backup_file" "CREATE TABLE"
    assert file_contains "$backup_file" "INSERT INTO"
}

@test "db-backup-restore: backup with auto-generated filename" {
    # Create backup directory
    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup without specifying filename
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -D "$TEST_BACKUP_DIR"

    assert_success

    # Check that a backup file was created
    local backup_count=$(find "$TEST_BACKUP_DIR" -name "*.sql" | wc -l)
    [ "$backup_count" -ge 1 ]
}

@test "db-backup-restore: schema-only backup" {
    local backup_file="${TEST_BACKUP_DIR}/test_schema_backup.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run schema-only backup
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --schema-only

    assert_success
    assert_file_exists "$backup_file"

    # Should contain table definitions but no data
    assert file_contains "$backup_file" "CREATE TABLE"
    ! file_contains "$backup_file" "INSERT INTO"
}

@test "db-backup-restore: data-only backup" {
    local backup_file="${TEST_BACKUP_DIR}/test_data_backup.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run data-only backup
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --data-only

    assert_success
    assert_file_exists "$backup_file"

    # Should contain data but no table definitions
    assert file_contains "$backup_file" "INSERT INTO" || file_contains "$backup_file" "COPY"
    ! file_contains "$backup_file" "CREATE TABLE"
}

# Test compression options
@test "db-backup-restore: backup with gzip compression" {
    local backup_file="${TEST_BACKUP_DIR}/test_gzip_backup.sql.gz"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup with gzip compression
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" -c gzip

    assert_success
    assert_file_exists "$backup_file"

    # Verify it's a gzip file
    file "$backup_file" | grep -q "gzip compressed"
}

@test "db-backup-restore: backup with bzip2 compression" {
    local backup_file="${TEST_BACKUP_DIR}/test_bzip2_backup.sql.bz2"

    mkdir -p "$TEST_BACKUP_DIR"

    # Skip if bzip2 is not available
    if ! command -v bzip2 >/dev/null 2>&1; then
        skip "bzip2 not available"
    fi

    # Run backup with bzip2 compression
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" -c bzip2

    assert_success
    assert_file_exists "$backup_file"

    # Verify it's a bzip2 file
    file "$backup_file" | grep -q "bzip2 compressed"
}

# Test different backup formats
@test "db-backup-restore: backup in custom format" {
    local backup_file="${TEST_BACKUP_DIR}/test_custom_backup.dump"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup in custom format
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --format custom

    assert_success
    assert_file_exists "$backup_file"

    # Custom format should be binary
    ! file_contains "$backup_file" "CREATE TABLE"
}

@test "db-backup-restore: backup in directory format" {
    local backup_dir="${TEST_BACKUP_DIR}/test_directory_backup"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup in directory format
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_dir" --format directory

    assert_success
    assert [ -d "$backup_dir" ]

    # Directory format should contain multiple files
    local file_count=$(find "$backup_dir" -type f | wc -l)
    [ "$file_count" -gt 1 ]
}

# Test table filtering
@test "db-backup-restore: backup specific tables" {
    local backup_file="${TEST_BACKUP_DIR}/test_specific_tables.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Backup only users table
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --include-table users

    assert_success
    assert_file_exists "$backup_file"

    # Should contain users table but not products table
    assert file_contains "$backup_file" "users"
    ! file_contains "$backup_file" "products"
}

@test "db-backup-restore: backup excluding tables" {
    local backup_file="${TEST_BACKUP_DIR}/test_exclude_tables.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Backup excluding temp tables
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --exclude-table "temp_*" --exclude-table "cache_*"

    assert_success
    assert_file_exists "$backup_file"

    # Should not contain temp or cache tables
    ! file_contains "$backup_file" "temp_logs"
    ! file_contains "$backup_file" "cache_data"
}

# Test parallel backup
@test "db-backup-restore: parallel backup" {
    local backup_dir="${TEST_BACKUP_DIR}/test_parallel_backup"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run parallel backup (requires directory format)
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_dir" \
        --format directory --jobs 2

    assert_success
    assert [ -d "$backup_dir" ]
}

# Test basic restore functionality
@test "db-backup-restore: basic database restore" {
    local backup_file="${TEST_BACKUP_DIR}/test_restore.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Create backup first
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    assert_success

    # Create target database for restore
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_restore_target" "$TEST_PASS_PRIMARY"

    # Run restore
    run_backup_restore_cmd restore \
        -f "$backup_file" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "test_restore_target"

    assert_success

    # Verify data was restored
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_restore_target" "$TEST_PASS_PRIMARY" "users"
    local user_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_restore_target" "$TEST_PASS_PRIMARY" "users")
    [ "$user_count" -ge 2 ]
}

@test "db-backup-restore: restore compressed backup" {
    local backup_file="${TEST_BACKUP_DIR}/test_compressed_restore.sql.gz"

    mkdir -p "$TEST_BACKUP_DIR"

    # Create compressed backup first
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" -c gzip

    assert_success

    # Create target database for restore
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_compressed_restore" "$TEST_PASS_PRIMARY"

    # Run restore
    run_backup_restore_cmd restore \
        -f "$backup_file" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "test_compressed_restore"

    assert_success

    # Verify data was restored
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_compressed_restore" "$TEST_PASS_PRIMARY" "users"
}

@test "db-backup-restore: restore custom format backup" {
    local backup_file="${TEST_BACKUP_DIR}/test_custom_restore.dump"

    mkdir -p "$TEST_BACKUP_DIR"

    # Create custom format backup first
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --format custom

    assert_success

    # Create target database for restore
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_custom_restore" "$TEST_PASS_PRIMARY"

    # Run restore
    run_backup_restore_cmd restore \
        -f "$backup_file" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "test_custom_restore"

    assert_success

    # Verify data was restored
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_custom_restore" "$TEST_PASS_PRIMARY" "users"
}

@test "db-backup-restore: restore with force (recreate database)" {
    local backup_file="${TEST_BACKUP_DIR}/test_force_restore.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Create backup first
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    assert_success

    # Create target database with some data
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_force_restore" "$TEST_PASS_PRIMARY"
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_force_restore" "$TEST_PASS_PRIMARY" \
        "CREATE TABLE temp_table (id int); INSERT INTO temp_table VALUES (1);"

    # Run restore with force
    run_backup_restore_cmd restore \
        -f "$backup_file" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-dbname "test_force_restore" --force

    assert_success

    # Verify database was recreated
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_force_restore" "$TEST_PASS_PRIMARY" "users"
    ! table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_force_restore" "$TEST_PASS_PRIMARY" "temp_table"
}

@test "db-backup-restore: restore with clean option" {
    local backup_file="${TEST_BACKUP_DIR}/test_clean_restore.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Create backup first
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    assert_success

    # Create target database with some data
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_clean_restore" "$TEST_PASS_PRIMARY"
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_clean_restore" "$TEST_PASS_PRIMARY" \
        "CREATE TABLE temp_table (id int); INSERT INTO temp_table VALUES (1);"

    # Run restore with clean
    run_backup_restore_cmd restore \
        -f "$backup_file" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "test_clean_restore" --clean

    assert_success

    # Verify data was restored and old data is gone
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_clean_restore" "$TEST_PASS_PRIMARY" "users"
}

# Test list functionality
@test "db-backup-restore: list backups in directory" {
    mkdir -p "$TEST_BACKUP_DIR"

    # Create a few backup files
    touch "${TEST_BACKUP_DIR}/backup1.sql"
    touch "${TEST_BACKUP_DIR}/backup2.sql.gz"
    touch "${TEST_BACKUP_DIR}/backup3.dump"

    # List backups
    run_backup_restore_cmd list -D "$TEST_BACKUP_DIR"

    assert_success
    assert_output --partial "backup1.sql"
    assert_output --partial "backup2.sql.gz"
    assert_output --partial "backup3.dump"
}

# Test validation functionality
@test "db-backup-restore: backup with validation" {
    local backup_file="${TEST_BACKUP_DIR}/test_validation.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup with validation
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --validate-schema

    assert_success
    assert_file_exists "$backup_file"
    assert_output --partial "validation" || assert_output --partial "verified"
}

# Test progress reporting
@test "db-backup-restore: backup with progress reporting" {
    local backup_file="${TEST_BACKUP_DIR}/test_progress.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup with progress
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --progress

    assert_success
    assert_file_exists "$backup_file"
    # Note: Progress output might not be visible in test environment
}

# Test verbose output
@test "db-backup-restore: backup with verbose output" {
    local backup_file="${TEST_BACKUP_DIR}/test_verbose.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup with verbose output
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --verbose

    assert_success
    assert_file_exists "$backup_file"

    # Should have more detailed output
    [ ${#lines[@]} -gt 3 ]
}

# Test logging functionality
@test "db-backup-restore: backup with log file" {
    local backup_file="${TEST_BACKUP_DIR}/test_logging.sql"
    local log_file="${TEST_BACKUP_DIR}/test_backup.log"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup with log file
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --log-file "$log_file"

    assert_success
    assert_file_exists "$backup_file"
    assert_file_exists "$log_file"

    # Log file should contain some information
    [ "$(get_file_size "$log_file")" -gt 0 ]
}

# Test error handling
@test "db-backup-restore: error on invalid database" {
    local backup_file="${TEST_BACKUP_DIR}/test_error.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Try to backup non-existent database
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_db" -f "$backup_file"

    assert_failure
    assert_output --partial "error" || assert_output --partial "failed" || assert_output --partial "does not exist"
}

@test "db-backup-restore: error on invalid connection" {
    local backup_file="${TEST_BACKUP_DIR}/test_connection_error.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Try to backup with invalid connection
    run_backup_restore_cmd backup \
        -H "invalid_host" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    assert_failure
}

@test "db-backup-restore: error on invalid backup file for restore" {
    # Try to restore non-existent file
    run_backup_restore_cmd restore \
        -f "/nonexistent/path/backup.sql" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"

    assert_failure
    assert_output --partial "error" || assert_output --partial "failed" || assert_output --partial "not found"
}

# Test configuration files
@test "db-backup-restore: save and load configuration" {
    local config_file="/tmp/test_backup_config.conf"
    local backup_file="${TEST_BACKUP_DIR}/test_config.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Clean up any existing config file
    rm -f "$config_file"

    # Save configuration
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --save-config "$config_file" --dry-run

    assert_success
    assert_file_exists "$config_file"

    # Load configuration and run backup
    run_backup_restore_cmd backup --load-config "$config_file"

    assert_success
    assert_file_exists "$backup_file"

    # Clean up
    rm -f "$config_file"
}

# Test include extensions
@test "db-backup-restore: backup with extensions" {
    local backup_file="${TEST_BACKUP_DIR}/test_extensions.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Run backup with extensions
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" --include-extensions

    assert_success
    assert_file_exists "$backup_file"

    # Should contain extension information
    assert file_contains "$backup_file" "EXTENSION" || file_contains "$backup_file" "CREATE EXTENSION"
}

# Performance test
@test "db-backup-restore: measure backup execution time" {
    local backup_file="${TEST_BACKUP_DIR}/test_timing.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Measure backup time
    local start_time=$(date +%s)

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    assert_success
    assert_file_exists "$backup_file"

    # Log execution time
    echo "Backup operation completed in ${duration} seconds" >&3
    [ "$duration" -lt 30 ]  # Should complete within 30 seconds for test data
}

# Test backup file size validation
@test "db-backup-restore: backup file should have reasonable size" {
    local backup_file="${TEST_BACKUP_DIR}/test_size.sql"

    mkdir -p "$TEST_BACKUP_DIR"

    # Create backup
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file"

    assert_success
    assert_file_exists "$backup_file"

    # Check file size is reasonable (should be > 1KB for test data)
    local file_size=$(get_file_size "$backup_file")
    [ "$file_size" -gt 1024 ]

    echo "Backup file size: ${file_size} bytes" >&3
}

# Enhanced backup/restore tests for missing features

# Test compression levels
@test "db-backup-restore: compression levels" {
    local backup_file="$BATS_TMPDIR/test_compress_levels.sql.gz"

    # Test different compression levels
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --compression gzip --compress-level 9

    assert_success
    assert_file_exists "$backup_file"

    # Verify the backup with highest compression
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    assert [ "$file_size" -gt 0 ]
}

# Test metrics file output
@test "db-backup-restore: metrics file generation" {
    local backup_file="$BATS_TMPDIR/test_metrics.sql"
    local metrics_file="$BATS_TMPDIR/test_metrics.csv"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --metrics-file "$metrics_file"

    assert_success
    assert_file_exists "$backup_file"
    assert_file_exists "$metrics_file"

    # Verify metrics file has expected headers
    run grep -q "operation,status,start_time,end_time,duration,file_size" "$metrics_file"
    assert_success
}

# Test backup manifest generation
@test "db-backup-restore: backup manifest" {
    local backup_file="$BATS_TMPDIR/test_manifest.sql"
    local manifest_file="${backup_file}.manifest"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --backup-manifest

    assert_success
    assert_file_exists "$backup_file"
    assert_file_exists "$manifest_file"

    # Verify manifest contains expected information
    run grep -q "backup_file\|database_name\|tables_count\|backup_size" "$manifest_file"
    assert_success
}

# Test schema validation
@test "db-backup-restore: schema validation" {
    local backup_file="$BATS_TMPDIR/test_schema_validation.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --validate-schema

    assert_success
    assert_file_exists "$backup_file"

    # Should include validation output in logs
    assert_output --partial "validation"
}

# Test constraint checking
@test "db-backup-restore: constraint checking" {
    local backup_file="$BATS_TMPDIR/test_constraints.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --check-constraints

    assert_success
    assert_file_exists "$backup_file"
}

# Test retry logic with simulated failures
@test "db-backup-restore: retry logic" {
    local backup_file="$BATS_TMPDIR/test_retry.sql"

    # Test retry parameters (won't actually fail, but tests parameter parsing)
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --retry-count 2 --retry-delay 1 --retry-backoff

    assert_success
    assert_file_exists "$backup_file"
}

# Test connection timeout
@test "db-backup-restore: connection timeout" {
    local backup_file="$BATS_TMPDIR/test_timeout.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --connection-timeout 30

    assert_success
    assert_file_exists "$backup_file"
}

# Test disk space check bypass
@test "db-backup-restore: bypass disk space check" {
    local backup_file="$BATS_TMPDIR/test_no_disk_check.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --no-disk-check

    assert_success
    assert_file_exists "$backup_file"
}

# Test directory format backup
@test "db-backup-restore: directory format backup" {
    local backup_dir="$BATS_TMPDIR/test_directory_backup"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_dir" \
        --format directory

    assert_success
    assert [ -d "$backup_dir" ]
    assert_file_exists "$backup_dir/toc.dat"
}

# Test webhook notification (mock webhook endpoint)
@test "db-backup-restore: webhook notification" {
    local backup_file="$BATS_TMPDIR/test_webhook.sql"

    # Skip if curl is not available
    if ! command -v curl >/dev/null 2>&1; then
        skip "curl not available for webhook testing"
    fi

    # Test with invalid webhook URL (should not fail backup)
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --notify-webhook "http://localhost:9999/invalid"

    assert_success
    assert_file_exists "$backup_file"
}

# Test SSL certificate parameters
@test "db-backup-restore: SSL certificate parameters" {
    local backup_file="$BATS_TMPDIR/test_ssl_cert.sql"

    # Test SSL mode parameter (should work with local connections)
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --ssl-mode prefer

    assert_success
    assert_file_exists "$backup_file"
}

# Test multiple schema inclusion/exclusion
@test "db-backup-restore: multiple schema operations" {
    local backup_file="$BATS_TMPDIR/test_multi_schema.sql"

    # Create additional schema
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE SCHEMA IF NOT EXISTS test_schema; CREATE TABLE test_schema.test_table (id INT);"

    # Test multiple schema inclusion
    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --schema public --schema test_schema

    assert_success
    assert_file_exists "$backup_file"
}

# Test large object handling
@test "db-backup-restore: large object exclusion" {
    local backup_file="$BATS_TMPDIR/test_no_large_objects.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --no-blobs

    assert_success
    assert_file_exists "$backup_file"
}

# Test backup timeout
@test "db-backup-restore: backup timeout" {
    local backup_file="$BATS_TMPDIR/test_backup_timeout.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --backup-timeout 300

    assert_success
    assert_file_exists "$backup_file"
}

# Test comprehensive error handling
@test "db-backup-restore: error handling - invalid database" {
    local backup_file="$BATS_TMPDIR/test_error.sql"

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_database" -f "$backup_file"

    assert_failure
    assert_output --partial "error"
}

# Test performance with large data
@test "db-backup-restore: performance with large dataset" {
    local backup_file="$BATS_TMPDIR/test_performance.sql"

    # Create larger dataset for performance testing
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "INSERT INTO users (name, email) SELECT 'user' || generate_series(1, 1000), 'user' || generate_series(1, 1000) || '@test.com';"

    local start_time=$(date +%s)

    run_backup_restore_cmd backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --jobs 2 --progress

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    assert_success
    assert_file_exists "$backup_file"

    # Performance should be reasonable (less than 30 seconds for test data)
    assert [ "$duration" -lt 30 ]
}
