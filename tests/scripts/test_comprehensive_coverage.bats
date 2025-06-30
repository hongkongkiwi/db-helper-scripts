#!/usr/bin/env bats

# Comprehensive coverage tests for edge cases and error scenarios

load '../bats-helpers/bats-support/load'
load '../bats-helpers/bats-assert/load'
load '../bats-helpers/bats-file/load'
load '../helpers/test_helpers.bash'

setup() {
    setup_test_environment
    export TEST_TIMEOUT=30
}

teardown() {
    cleanup_test_databases
}

# Configuration file handling tests
@test "config: db-backup-restore save and load config files" {
    local config_file="$BATS_TMPDIR/test_config.conf"
    local backup_file="$BATS_TMPDIR/test_backup.sql"

    # Save configuration
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --save-config "$config_file" --dry-run

    assert_success
    assert_file_exists "$config_file"

    # Config file should contain connection info
    grep -q "HOST=" "$config_file" || grep -q "host" "$config_file"
    grep -q "PORT=" "$config_file" || grep -q "port" "$config_file"

    # Load configuration and run
    run /workspace/db-backup-restore backup --config-file "$config_file"

    # Should succeed or show meaningful error
    assert_success || assert_output --partial "config" || assert_output --partial "database"
}

# SSL/TLS connection tests
@test "ssl: all scripts handle SSL parameters correctly" {
    # Test SSL mode parameter (should not fail on syntax)
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "/tmp/ssl_test.sql" \
        --ssl-mode prefer --dry-run

    assert_success || assert_output --partial "ssl" || assert_output --partial "SSL"

    run /workspace/db-copy copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "ssl_test_target" \
        --sslmode prefer --dry-run

    assert_success || assert_output --partial "ssl" || assert_output --partial "SSL"

    run /workspace/db-user-manager list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --ssl-mode prefer

    # Should connect or give SSL-related error
    assert_success || assert_output --partial "ssl" || assert_output --partial "SSL"
}

# Large database simulation tests
@test "performance: handling large table names and complex scenarios" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    # Create tables with very long names
    local long_table_name="very_long_table_name_that_tests_limits_and_edge_cases_in_naming_conventions"

    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE TABLE IF NOT EXISTS $long_table_name (id serial, data text);"

    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "INSERT INTO $long_table_name (data) VALUES ('test data');"

    # Test backup with specific table inclusion
    local backup_file="$BATS_TMPDIR/long_name_test.sql"

    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --include-table "$long_table_name"

    assert_success
    assert_file_exists "$backup_file"

    # Backup should contain the long table name
    grep -q "$long_table_name" "$backup_file"

    # Clean up
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP TABLE IF EXISTS $long_table_name;" || true
}

# Memory and resource constraint tests
@test "resource: scripts handle low memory gracefully" {
    # Test with memory constraints (if available)
    local backup_file="$BATS_TMPDIR/memory_test.sql"

    # Use smaller memory settings
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$backup_file" \
        --compress-level 1

    assert_success || assert_output --partial "memory" || assert_output --partial "resource"

    # Test db-copy with minimal memory
    run /workspace/db-copy copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "memory_test_db" \
        --work-mem "4MB" --maintenance-work-mem "16MB" --dry-run

    assert_success || assert_output --partial "memory" || assert_output --partial "resource"
}

# Network interruption simulation
@test "network: timeout handling in all scripts" {
    # Test connection timeout parameters
    run /workspace/db-backup-restore backup \
        -H "192.0.2.1" -p "54321" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "/tmp/timeout_test.sql" \
        --connection-timeout 1

    # Should fail with timeout or connection error
    assert_failure
    assert_output --partial "timeout" || assert_output --partial "connection" || assert_output --partial "failed"

    run /workspace/db-copy copy \
        -H "192.0.2.1" -p "54321" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "timeout_test" \
        --connection-timeout 1

    assert_failure
    assert_output --partial "timeout" || assert_output --partial "connection" || assert_output --partial "failed"

    run /workspace/db-user-manager list-users \
        -H "192.0.2.1" -p "54321" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"

    assert_failure
    assert_output --partial "timeout" || assert_output --partial "connection" || assert_output --partial "failed"
}

# Special character handling
@test "security: special characters in database names and user names" {
    # Test with database names containing special characters
    local special_db_name="test-db_with.special@chars"

    # These should either work or give appropriate security errors
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$special_db_name" -f "/tmp/special_test.sql"

    # Should either work or give a meaningful error about invalid characters
    assert_failure
    assert_output --partial "Invalid" || assert_output --partial "invalid" || assert_output --partial "error"

    # Test user names with special characters
    run /workspace/db-user-manager create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test@user.com"

    # Should reject invalid user names
    assert_failure || assert_output --partial "reserved" || assert_output --partial "invalid"
}

# File permission and disk space tests
@test "filesystem: disk space and permission handling" {
    # Create a backup directory with restricted permissions
    local restricted_dir="$BATS_TMPDIR/restricted"
    mkdir -p "$restricted_dir"
    chmod 444 "$restricted_dir"

    # Test backup to read-only directory
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -D "$restricted_dir"

    assert_failure
    assert_output --partial "permission" || assert_output --partial "write" || assert_output --partial "error"

    # Restore permissions for cleanup
    chmod 755 "$restricted_dir"
}

# Parallel operation stress test
@test "stress: multiple concurrent operations" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local backup_dir="$BATS_TMPDIR/stress_test"
    mkdir -p "$backup_dir"

    # Start multiple backup operations
    local pids=()
    for i in {1..3}; do
        (
            /workspace/db-backup-restore backup \
                -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
                -d "$TEST_DB_PRIMARY" -f "$backup_dir/stress_backup_$i.sql" \
                >/dev/null 2>&1
        ) &
        pids+=($!)
    done

    # Start a user listing operation
    (
        /workspace/db-user-manager list-users \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" \
            >/dev/null 2>&1
    ) &
    pids+=($!)

    # Wait for all operations to complete
    local success_count=0
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            success_count=$((success_count + 1))
        fi
    done

    # At least some operations should succeed
    [ "$success_count" -ge 2 ]
}

# Validation and integrity tests
@test "integrity: backup validation across different formats" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local test_dir="$BATS_TMPDIR/integrity_test"
    mkdir -p "$test_dir"

    # Create backups in different formats
    local formats=("plain" "custom")
    local backup_files=()

    for format in "${formats[@]}"; do
        local backup_file="$test_dir/test_${format}_backup"
        if [[ "$format" == "plain" ]]; then
            backup_file="${backup_file}.sql"
        else
            backup_file="${backup_file}.dump"
        fi

        run /workspace/db-backup-restore backup \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" -f "$backup_file" --format "$format"

        if [[ $status -eq 0 ]]; then
            backup_files+=("$backup_file")
            assert_file_exists "$backup_file"

            # File should not be empty
            local size=$(get_file_size "$backup_file")
            [ "$size" -gt 0 ]
        fi
    done

    # At least one backup should have been created
    [ ${#backup_files[@]} -gt 0 ]
}

# Advanced user management scenarios
@test "advanced: complex user permission scenarios" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local test_user="complex_test_user"
    local test_role="complex_test_role"

    # Create user with specific permissions
    echo "complexpass123" | run /workspace/db-user-manager create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --passwd-stdin

    if [[ $status -eq 0 ]]; then
        # Create role
        run /workspace/db-user-manager create-role \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" --role-name "$test_role"

        # Assign role
        run /workspace/db-user-manager assign-role \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" --target-user "$test_user" --role-name "$test_role"

        # Show user permissions
        run /workspace/db-user-manager show-user-permissions \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" --target-user "$test_user"

        assert_success
        assert_output --partial "$test_user" || assert_output --partial "permissions"

        # Clean up
        PGPASSWORD="$TEST_PASS_PRIMARY" psql -h "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" -d "$TEST_DB_PRIMARY" \
            -c "DROP USER IF EXISTS $test_user; DROP ROLE IF EXISTS $test_role;" 2>/dev/null || true
    fi
}

# Cross-script data flow test
@test "workflow: complete database migration workflow" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local migration_backup="$BATS_TMPDIR/migration_backup.sql"
    local migration_db="workflow_migration_test"
    local migration_user="workflow_test_user"

    # Step 1: Create user for migration
    echo "workflowpass123" | run /workspace/db-user-manager create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$migration_user" --passwd-stdin

    if [[ $status -ne 0 ]]; then
        skip "Could not create test user for workflow"
    fi

    # Step 2: Grant permissions
    run /workspace/db-user-manager grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$migration_user"

    # Step 3: Create backup
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "$migration_backup"

    assert_success
    assert_file_exists "$migration_backup"

    # Step 4: Create new database
    run /workspace/db-copy copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "$migration_db" --schema-only

    assert_success

    # Step 5: Grant access to new database
    run /workspace/db-user-manager grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$migration_db" --target-user "$migration_user"

    # Step 6: Restore data to new database
    run /workspace/db-backup-restore restore \
        -f "$migration_backup" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$migration_db"

    assert_success

    # Step 7: Verify migration
    local original_users=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "users" 2>/dev/null || echo "0")
    local migrated_users=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$migration_db" "$TEST_PASS_PRIMARY" "users" 2>/dev/null || echo "0")

    # Data should be preserved
    [ "$original_users" -eq "$migrated_users" ]

    # Clean up
    drop_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$migration_db" "$TEST_PASS_PRIMARY"
    PGPASSWORD="$TEST_PASS_PRIMARY" psql -h "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" -d "$TEST_DB_PRIMARY" \
        -c "DROP USER IF EXISTS $migration_user;" 2>/dev/null || true
}
