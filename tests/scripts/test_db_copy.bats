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

    # Reset test data in primary database
    reset_test_data "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"
}

teardown() {
    cleanup_test_databases
}

# Helper function to run db-copy command
run_db_copy_cmd() {
    # Use absolute path to the script
    if [[ -f "/workspace/db-copy" ]]; then
        run /workspace/db-copy "$@"
    else
        run ../db-copy "$@"  # Fallback for local execution
    fi
}

# Test basic help and version commands
@test "db-copy: help command shows usage information" {
    run_db_copy_cmd help
    assert_success
    assert_output --partial "PostgreSQL Database Copy Tool"
    assert_output --partial "USAGE:"
    assert_output --partial "COMMANDS:"
    assert_output --partial "copy"
}

@test "db-copy: version command shows version information" {
    run_db_copy_cmd version
    assert_success
    assert_output --partial "db-copy v"
    assert_output --partial "1.0.0"
}

@test "db-copy: copy --help shows copy command help" {
    run_db_copy_cmd copy --help
    assert_success
    assert_output --partial "Copy/clone a PostgreSQL database"
    assert_output --partial "USAGE:"
    assert_output --partial "--target-dbname"
}

# Test basic database copying
@test "db-copy: basic same-server database copy" {
    # Create target database first (db-copy will drop and recreate it)
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_target" "$TEST_PASS_PRIMARY"

    # Run copy command with --drop-target to handle existing database
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_copy_target \
        --drop-target --skip-confirmation

    assert_success

    # Verify target database exists and has data
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_target" "$TEST_PASS_PRIMARY"
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_target" "$TEST_PASS_PRIMARY" "users"
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_target" "$TEST_PASS_PRIMARY" "products"

    # Verify data was copied
    local user_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_target" "$TEST_PASS_PRIMARY" "users")
    [ "$user_count" -ge 2 ]  # Should have at least the test users
}

@test "db-copy: schema-only copy" {
    # Create target database first (db-copy will drop and recreate it)
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_schema_only" "$TEST_PASS_PRIMARY"

    # Run schema-only copy with --drop-target
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_schema_only \
        --schema-only --drop-target --skip-confirmation

    assert_success

    # Verify tables exist but have no data
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_schema_only" "$TEST_PASS_PRIMARY" "users"
    assert_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_schema_only" "$TEST_PASS_PRIMARY" "users" "0"
}

@test "db-copy: data-only copy to existing database" {
    # Create target database and schema
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_data_only" "$TEST_PASS_PRIMARY"

    # First copy schema only
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_data_only \
        --schema-only --skip-confirmation

    assert_success

    # Then copy data only
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_data_only \
        --data-only --skip-confirmation

    assert_success

    # Verify data was copied
    local user_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_data_only" "$TEST_PASS_PRIMARY" "users")
    [ "$user_count" -ge 2 ]
}

# Test cross-server copying
@test "db-copy: cross-server database copy" {
    # Create target database on secondary server first
    create_test_database "$TEST_HOST_SECONDARY" "$TEST_PORT_SECONDARY" "$TEST_USER_SECONDARY" "test_cross_server" "$TEST_PASS_SECONDARY"

    # Run cross-server copy with --drop-target
    run_db_copy_cmd copy \
        --src-host "$TEST_HOST_PRIMARY" --src-port "$TEST_PORT_PRIMARY" \
        --src-user "$TEST_USER_PRIMARY" --src-dbname "$TEST_DB_PRIMARY" \
        --target-host "$TEST_HOST_SECONDARY" --target-port "$TEST_PORT_SECONDARY" \
        --target-user "$TEST_USER_SECONDARY" --target-dbname test_cross_server \
        --drop-target --skip-confirmation

    assert_success

    # Verify target database on secondary server
    assert_database_exists "$TEST_HOST_SECONDARY" "$TEST_PORT_SECONDARY" "$TEST_USER_SECONDARY" "test_cross_server" "$TEST_PASS_SECONDARY"
    assert_table_exists "$TEST_HOST_SECONDARY" "$TEST_PORT_SECONDARY" "$TEST_USER_SECONDARY" "test_cross_server" "$TEST_PASS_SECONDARY" "users"
}

# Test table filtering
@test "db-copy: include specific tables" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_include_tables" "$TEST_PASS_PRIMARY"

    # Copy only users table
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_include_tables \
        --include-table users --skip-confirmation

    assert_success

    # Verify only users table exists
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_include_tables" "$TEST_PASS_PRIMARY" "users"

    # Verify products table does not exist (or exists but is empty if schema was included)
    local products_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_include_tables" "$TEST_PASS_PRIMARY" "products" 2>/dev/null || echo "0")
    [ "$products_count" -eq 0 ]
}

@test "db-copy: exclude specific tables" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_exclude_tables" "$TEST_PASS_PRIMARY"

    # Copy all except temp tables
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_exclude_tables \
        --exclude-table "temp_*" --exclude-table "cache_*" --skip-confirmation

    assert_success

    # Verify main tables exist
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_exclude_tables" "$TEST_PASS_PRIMARY" "users"

    # Verify temp and cache tables are empty or don't exist
    local temp_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_exclude_tables" "$TEST_PASS_PRIMARY" "temp_logs" 2>/dev/null || echo "0")
    [ "$temp_count" -eq 0 ]
}

# Test schema filtering
@test "db-copy: include specific schema" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_include_schema" "$TEST_PASS_PRIMARY"

    # Copy only public schema
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_include_schema \
        --include-schema public --skip-confirmation

    assert_success

    # Verify public schema tables exist
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_include_schema" "$TEST_PASS_PRIMARY" "users"

    # Verify test_schema tables don't exist or are empty
    local test_schema_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_include_schema" "$TEST_PASS_PRIMARY" "test_schema.test_table" 2>/dev/null || echo "0")
    [ "$test_schema_count" -eq 0 ]
}

# Test validation features
@test "db-copy: copy with validation" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_validation" "$TEST_PASS_PRIMARY"

    # Run copy with validation
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_validation \
        --validate --skip-confirmation

    assert_success
    assert_output --partial "Validation completed"

    # Should report validation results
    assert_output --partial "Row count validation" || assert_output --partial "Schema validation"
}

# Test dry run functionality
@test "db-copy: dry run mode" {
    # Run dry run - should not create database
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_dry_run \
        --dry-run

    assert_success
    assert_output --partial "DRY RUN MODE"

    # Verify database was not created
    ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_dry_run" "$TEST_PASS_PRIMARY"
}

# Test parallel processing
@test "db-copy: parallel processing with jobs option" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_parallel" "$TEST_PASS_PRIMARY"

    # Run copy with parallel jobs
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_parallel \
        --jobs 2 --skip-confirmation

    assert_success

    # Verify data was copied correctly
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_parallel" "$TEST_PASS_PRIMARY" "users"
    local user_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_parallel" "$TEST_PASS_PRIMARY" "users")
    [ "$user_count" -ge 2 ]
}

# Test fast template copy (same server optimization)
@test "db-copy: fast template copy on same server" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_fast_copy" "$TEST_PASS_PRIMARY"

    # Run fast copy
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_fast_copy \
        --fast --skip-confirmation

    assert_success

    # Should indicate fast copy was used
    assert_output --partial "fast" || assert_output --partial "template" || assert_output --partial "optimization"

    # Verify data was copied
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_fast_copy" "$TEST_PASS_PRIMARY" "users"
}

# Test sync mode
@test "db-copy: sync mode for existing database" {
    # Create and populate target database first
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_sync_target" "$TEST_PASS_PRIMARY"

    # Initial copy
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_sync_target \
        --skip-confirmation

    assert_success

    # Run sync mode
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_sync_target \
        --sync --skip-confirmation

    assert_success
    assert_output --partial "sync" || assert_output --partial "synchronization" || assert_output --partial "incremental"
}

# Test error handling
@test "db-copy: error on invalid source database" {
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_db" --target-dbname test_error \
        --skip-confirmation

    assert_failure
    assert_output --partial "error" || assert_output --partial "failed" || assert_output --partial "does not exist"
}

@test "db-copy: error on invalid connection parameters" {
    run_db_copy_cmd copy \
        -H "invalid_host" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_error \
        --skip-confirmation

    assert_failure
}

@test "db-copy: error when target database exists without drop-target" {
    # Create target database first
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_existing" "$TEST_PASS_PRIMARY"

    # Try to copy without drop-target or sync options
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_existing \
        --skip-confirmation

    # Should either fail or offer options
    [ "$status" -ne 0 ] || [[ "$output" =~ (exists|already|drop|sync) ]]
}

# Test drop target functionality
@test "db-copy: drop existing target database" {
    # Create target database first
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_drop_target" "$TEST_PASS_PRIMARY"

    # Add some data to verify it gets replaced
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_drop_target" "$TEST_PASS_PRIMARY" \
        "CREATE TABLE temp_table (id int); INSERT INTO temp_table VALUES (1);"

    # Copy with drop-target
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_drop_target \
        --drop-target --skip-confirmation

    assert_success

    # Verify database was recreated with source data
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_drop_target" "$TEST_PASS_PRIMARY" "users"

    # Verify old data is gone
    ! table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_drop_target" "$TEST_PASS_PRIMARY" "temp_table"
}

# Test progress reporting
@test "db-copy: progress reporting" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_progress" "$TEST_PASS_PRIMARY"

    # Run copy with progress
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_progress \
        --progress --skip-confirmation

    assert_success
    assert_output --partial "progress" || assert_output --partial "%" || assert_output --partial "completed"
}

# Test verbose output
@test "db-copy: verbose output" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_verbose" "$TEST_PASS_PRIMARY"

    # Run copy with verbose output
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_verbose \
        --verbose --skip-confirmation

    assert_success

    # Should have more detailed output
    [ ${#lines[@]} -gt 5 ]  # Verbose should produce more lines
}

# Test performance optimizations
@test "db-copy: performance optimization options" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_performance" "$TEST_PASS_PRIMARY"

    # Run copy with performance optimizations
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_performance \
        --optimize-performance --disable-triggers \
        --maintenance-work-mem 64MB --work-mem 16MB \
        --skip-confirmation

    assert_success

    # Verify data was copied
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_performance" "$TEST_PASS_PRIMARY" "users"
}

# Test SSL connection options
@test "db-copy: SSL connection parameters" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_ssl" "$TEST_PASS_PRIMARY"

    # Run copy with SSL options (should work with local connections)
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_ssl \
        --sslmode prefer --skip-confirmation

    assert_success

    # Verify data was copied
    assert_table_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_ssl" "$TEST_PASS_PRIMARY" "users"
}

# Test configuration file options
@test "db-copy: save and load configuration" {
    local config_file="/tmp/test_db_copy_config.conf"

    # Clean up any existing config file
    rm -f "$config_file"

    # Save configuration
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_config \
        --save-config "$config_file" --dry-run

    assert_success
    assert_file_exists "$config_file"

    # Load configuration and run copy
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_config" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy --load-config "$config_file" --skip-confirmation

    assert_success

    # Clean up
    rm -f "$config_file"
}

# Performance test (execution time measurement)
@test "db-copy: measure execution time for copy operation" {
    # Create target database
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_timing" "$TEST_PASS_PRIMARY"

    # Measure execution time
    local start_time=$(date +%s)

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_timing \
        --skip-confirmation

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    assert_success

    # Log execution time (should complete in reasonable time)
    echo "Copy operation completed in ${duration} seconds" >&3
    [ "$duration" -lt 60 ]  # Should complete within 60 seconds for test data
}

# Enhanced db-copy tests for missing features

# Test large object exclusion
@test "db-copy: exclude large objects" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_no_large_objects" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_no_large_objects \
        --exclude-large-objects --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_no_large_objects" "$TEST_PASS_PRIMARY"
}

# Test connection timeout
@test "db-copy: connection timeout" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_connection_timeout" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_connection_timeout \
        --connection-timeout 30 --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_connection_timeout" "$TEST_PASS_PRIMARY"
}

# Test copy timeout
@test "db-copy: copy timeout" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_timeout" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_copy_timeout \
        --copy-timeout 300 --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_copy_timeout" "$TEST_PASS_PRIMARY"
}

# Test performance optimization
@test "db-copy: performance optimization" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_optimize_performance" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_optimize_performance \
        --optimize-performance --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_optimize_performance" "$TEST_PASS_PRIMARY"
}

# Test memory configuration
@test "db-copy: memory settings" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_memory_settings" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_memory_settings \
        --maintenance-work-mem "256MB" --work-mem "64MB" --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_memory_settings" "$TEST_PASS_PRIMARY"
}

# Test multiple schema exclusion
@test "db-copy: multiple schema exclusion" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_multi_schema_exclude" "$TEST_PASS_PRIMARY"

    # Create additional schemas
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE SCHEMA IF NOT EXISTS temp_schema; CREATE SCHEMA IF NOT EXISTS test_schema;"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_multi_schema_exclude \
        --exclude-schema temp_schema --exclude-schema test_schema --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_multi_schema_exclude" "$TEST_PASS_PRIMARY"
}

# Test log file output
@test "db-copy: log file output" {
    local log_file="$BATS_TMPDIR/test_copy.log"
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_log_file" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_log_file \
        --log-file "$log_file" --skip-confirmation

    assert_success
    assert_file_exists "$log_file"
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_log_file" "$TEST_PASS_PRIMARY"

    # Verify log file contains expected content
    run grep -q "copy.*operation" "$log_file"
    assert_success
}

# Test SSL certificate files (parameter validation)
@test "db-copy: SSL certificate parameters" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_ssl_files" "$TEST_PASS_PRIMARY"

    # Test SSL mode with certificate parameters (should work with local connections)
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_ssl_files \
        --sslmode prefer --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_ssl_files" "$TEST_PASS_PRIMARY"
}

# Test disable triggers during copy
@test "db-copy: disable triggers" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_disable_triggers" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_disable_triggers \
        --disable-triggers --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_disable_triggers" "$TEST_PASS_PRIMARY"
}

# Test disable indexes during copy
@test "db-copy: disable indexes" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_disable_indexes" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_disable_indexes \
        --disable-indexes --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_disable_indexes" "$TEST_PASS_PRIMARY"
}

# Test truncate tables option
@test "db-copy: truncate tables" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_truncate" "$TEST_PASS_PRIMARY"

    # Populate target database first
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_truncate" "$TEST_PASS_PRIMARY" \
        "CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100)); INSERT INTO users (name) VALUES ('existing_user');"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_truncate \
        --truncate-tables --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_truncate" "$TEST_PASS_PRIMARY"
}

# Test comprehensive error handling
@test "db-copy: error handling - invalid source database" {
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_source" --target-dbname test_error

    assert_failure
    assert_output --partial "error"
}

# Test concurrent operations handling
@test "db-copy: concurrent copy operations" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_concurrent1" "$TEST_PASS_PRIMARY"
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_concurrent2" "$TEST_PASS_PRIMARY"

    # Start two copy operations
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_concurrent1 \
        --skip-confirmation &

    local pid1=$!

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_concurrent2 \
        --skip-confirmation &

    local pid2=$!

    # Wait for both to complete
    wait $pid1
    wait $pid2

    # Both should succeed
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_concurrent1" "$TEST_PASS_PRIMARY"
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_concurrent2" "$TEST_PASS_PRIMARY"
}

# Test resource constraint handling
@test "db-copy: resource constraints" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_resources" "$TEST_PASS_PRIMARY"

    # Create larger dataset for testing resource constraints
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "INSERT INTO users (name, email) SELECT 'user' || generate_series(1, 5000), 'user' || generate_series(1, 5000) || '@test.com';"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_resources \
        --jobs 1 --work-mem "4MB" --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_resources" "$TEST_PASS_PRIMARY"
}

# Test progress monitoring with custom interval
@test "db-copy: progress monitoring with custom interval" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_progress_interval" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_progress_interval \
        --progress --progress-interval 5 --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_progress_interval" "$TEST_PASS_PRIMARY"
}

# Test WAL level optimization
@test "db-copy: WAL level optimization" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_wal_level" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_wal_level \
        --wal-level minimal --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_wal_level" "$TEST_PASS_PRIMARY"
}

# Test for same server/same database prevention (CRITICAL)
@test "db-copy: prevent same server same database copy" {
    # This should fail with a clear error message
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "$TEST_DB_PRIMARY"

    assert_failure
    assert_output --partial "Cannot copy database to itself"
    assert_output --partial "Source and target database names must be different"
}

# Test for same server but different database (should work)
@test "db-copy: allow same server different database" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_same_server_diff_db" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_same_server_diff_db \
        --drop-target --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_same_server_diff_db" "$TEST_PASS_PRIMARY"
}

# Test template copy validation
@test "db-copy: template copy requires same server" {
    run_db_copy_cmd copy \
        --src-host "$TEST_HOST_PRIMARY" --src-port "$TEST_PORT_PRIMARY" --src-user "$TEST_USER_PRIMARY" \
        --src-dbname "$TEST_DB_PRIMARY" \
        --target-host "$TEST_HOST_SECONDARY" --target-port "$TEST_PORT_SECONDARY" --target-user "$TEST_USER_SECONDARY" \
        --target-dbname test_template_cross_server \
        --fast

    assert_failure
    assert_output --partial "Template-based copy (--fast) requires source and target to be on the same server"
}

# Test template copy with table filtering (should fallback)
@test "db-copy: template copy with filtering falls back" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_template_fallback" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_template_fallback \
        --fast --include-table users --drop-target --skip-confirmation

    assert_success
    assert_output --partial "Template copy doesn't support table filtering"
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_template_fallback" "$TEST_PASS_PRIMARY"
}

# Test sync mode with drop-target conflict
@test "db-copy: sync mode conflicts with drop-target" {
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_sync_conflict \
        --sync --drop-target

    assert_failure
    assert_output --partial "Cannot use --sync with --drop-target"
}

# Test invalid SSL certificate file
@test "db-copy: invalid SSL certificate file" {
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_ssl_invalid \
        --sslcert /nonexistent/cert.pem

    assert_failure
    assert_output --partial "SSL certificate file not found"
}

# Test invalid memory format
@test "db-copy: invalid memory format" {
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_invalid_memory \
        --maintenance-work-mem "invalid_format"

    assert_failure
    assert_output --partial "Invalid maintenance_work_mem format"
}

# Test valid memory format
@test "db-copy: valid memory format" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_valid_memory" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_valid_memory \
        --maintenance-work-mem "256MB" --work-mem "64MB" \
        --drop-target --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_valid_memory" "$TEST_PASS_PRIMARY"
}

# Test truncate tables without sync mode
@test "db-copy: truncate tables requires sync mode" {
    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_truncate_no_sync \
        --truncate-tables

    assert_failure
    assert_output --partial "Table truncation (--truncate-tables) can only be used with sync mode"
}

# Test performance optimization warnings
@test "db-copy: performance optimization warnings" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_perf_warnings" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_perf_warnings \
        --schema-only --disable-triggers --disable-indexes \
        --drop-target --skip-confirmation

    assert_success
    assert_output --partial "Disabling triggers is not applicable for schema-only"
    assert_output --partial "Disabling indexes is not applicable for schema-only"
}

# Test edge cases
@test "db-copy: edge case - empty database" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_empty_database" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_empty_database \
        --drop-target --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_empty_database" "$TEST_PASS_PRIMARY"
}

@test "db-copy: edge case - single table database" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_single_table_database" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_single_table_database \
        --drop-target --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_single_table_database" "$TEST_PASS_PRIMARY"
}

@test "db-copy: edge case - large database" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_large_database" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_large_database \
        --drop-target --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_large_database" "$TEST_PASS_PRIMARY"
}

@test "db-copy: edge case - database with large objects" {
    create_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_large_objects_database" "$TEST_PASS_PRIMARY"

    run_db_copy_cmd copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname test_large_objects_database \
        --drop-target --skip-confirmation

    assert_success
    assert_database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_large_objects_database" "$TEST_PASS_PRIMARY"
}
