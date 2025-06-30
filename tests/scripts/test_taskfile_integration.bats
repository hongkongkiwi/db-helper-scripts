#!/usr/bin/env bats

# Integration tests for Taskfile.yml and cross-script functionality

load '../bats-helpers/bats-support/load'
load '../bats-helpers/bats-assert/load'
load '../bats-helpers/bats-file/load'
load '../helpers/test_helpers.bash'

setup() {
    # Set up test environment
    export ORIGINAL_DIR="$(pwd)"
    cd /workspace

    # Create temporary home for testing
    export ORIGINAL_HOME="$HOME"
    export HOME="$BATS_TMPDIR/test_home"
    mkdir -p "$HOME/.local/bin"
}

teardown() {
    # Restore environment
    cd "$ORIGINAL_DIR"
    export HOME="$ORIGINAL_HOME"

    # Clean up any test installations
    rm -rf "$BATS_TMPDIR/test_home"
}

# Test Taskfile.yml exists and is valid
@test "taskfile: Taskfile.yml exists and is readable" {
    [ -f "/workspace/Taskfile.yml" ]
    [ -r "/workspace/Taskfile.yml" ]
}

@test "taskfile: contains required tasks" {
    # Check for essential tasks
    grep -q "install:" /workspace/Taskfile.yml
    grep -q "uninstall:" /workspace/Taskfile.yml
    grep -q "update:" /workspace/Taskfile.yml
    grep -q "dev:test:" /workspace/Taskfile.yml
    grep -q "dev:lint:" /workspace/Taskfile.yml
    grep -q "check:deps:" /workspace/Taskfile.yml
}

@test "taskfile: task command detection" {
    # Check if task is available (skip if not installed)
    if ! command -v task >/dev/null 2>&1; then
        skip "Task not available in test environment"
    fi

    # Test task listing works
    run task --list
    assert_success
    assert_output --partial "install"
    assert_output --partial "uninstall"
}

# Test script integration - backup and restore workflow
@test "integration: full backup and restore workflow" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local backup_dir="$BATS_TMPDIR/integration_backup"
    local restore_db="integration_test_restore"

    mkdir -p "$backup_dir"

    # Step 1: Create backup using db-backup-restore
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -D "$backup_dir" --format plain

    assert_success

    # Find the created backup file
    local backup_file=$(find "$backup_dir" -name "*.sql" | head -1)
    [ -f "$backup_file" ]

    # Step 2: Create new database using db-copy (for setup)
    run /workspace/db-copy copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "$restore_db" --schema-only

    assert_success

    # Step 3: Restore data using db-backup-restore
    run /workspace/db-backup-restore restore \
        -f "$backup_file" \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$restore_db"

    assert_success

    # Step 4: Verify data integrity
    local original_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "users")
    local restored_count=$(get_row_count "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$restore_db" "$TEST_PASS_PRIMARY" "users")

    [ "$original_count" -eq "$restored_count" ]

    # Clean up
    drop_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$restore_db" "$TEST_PASS_PRIMARY"
}

# Test script integration - user management with database copying
@test "integration: user creation and database copying with permissions" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local test_user="integration_test_user"
    local copy_db="integration_test_copy"

    # Step 1: Create test user with db-user-manager
    echo "testpass123" | run /workspace/db-user-manager create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --passwd-stdin

    assert_success

    # Step 2: Grant permissions
    run /workspace/db-user-manager grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user"

    assert_success

    # Step 3: Copy database with db-copy
    run /workspace/db-copy copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "$copy_db"

    assert_success

    # Step 4: Verify user exists in original database
    assert user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$test_user" "$TEST_PASS_PRIMARY"

    # Step 5: Grant access to copied database
    run /workspace/db-user-manager grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$copy_db" --target-user "$test_user"

    assert_success

    # Clean up
    drop_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$copy_db" "$TEST_PASS_PRIMARY"

    # Drop user (may fail if dependencies exist, which is fine)
    PGPASSWORD="$TEST_PASS_PRIMARY" psql -h "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" -d "$TEST_DB_PRIMARY" \
        -c "DROP USER IF EXISTS $test_user;" 2>/dev/null || true
}

# Test error handling across scripts
@test "integration: consistent error handling across scripts" {
    # Test that all scripts handle invalid database consistently
    run /workspace/db-backup-restore backup \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_database" -f "/tmp/test.sql"
    assert_failure

    run /workspace/db-copy copy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_database" --target-dbname "test_target"
    assert_failure

    run /workspace/db-user-manager list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_database"
    assert_failure
}

@test "integration: consistent connection error handling" {
    # Test that all scripts handle invalid host consistently
    run /workspace/db-backup-restore backup \
        -H "invalid_host_name" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" -f "/tmp/test.sql"
    assert_failure

    run /workspace/db-copy copy \
        -H "invalid_host_name" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-dbname "test_target"
    assert_failure

    run /workspace/db-user-manager list-users \
        -H "invalid_host_name" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"
    assert_failure
}

# Test version consistency
@test "integration: all scripts report versions" {
    run /workspace/db-backup-restore version
    assert_success
    assert_output --partial "version"

    run /workspace/db-copy version
    assert_success
    assert_output --partial "version"

    run /workspace/db-user-manager version
    assert_success
    assert_output --partial "version"
}

# Test help consistency
@test "integration: all scripts provide comprehensive help" {
    # All scripts should have help command
    run /workspace/db-backup-restore help
    assert_success
    assert_output --partial "USAGE"
    assert_output --partial "COMMANDS"
    assert_output --partial "OPTIONS"

    run /workspace/db-copy help
    assert_success
    assert_output --partial "USAGE"
    assert_output --partial "COMMANDS"
    assert_output --partial "OPTIONS"

    run /workspace/db-user-manager help
    assert_success
    assert_output --partial "USAGE"
    assert_output --partial "COMMANDS"
    assert_output --partial "OPTIONS"
}

# Test performance under parallel operations
@test "integration: parallel operations don't interfere" {
    # Skip if test database not available
    if ! database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY"; then
        skip "Test database not available"
    fi

    local backup_dir="$BATS_TMPDIR/parallel_test"
    mkdir -p "$backup_dir"

    # Start multiple operations in background
    (
        /workspace/db-backup-restore backup \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" -f "$backup_dir/backup1.sql" \
            >/dev/null 2>&1
    ) &
    local backup_pid=$!

    (
        /workspace/db-user-manager list-users \
            -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
            -d "$TEST_DB_PRIMARY" \
            >/dev/null 2>&1
    ) &
    local list_pid=$!

    # Wait for both to complete
    wait $backup_pid
    local backup_status=$?

    wait $list_pid
    local list_status=$?

    # Both should succeed
    [ $backup_status -eq 0 ]
    [ $list_status -eq 0 ]

    # Backup file should be created
    [ -f "$backup_dir/backup1.sql" ]
}

# Test configuration consistency
@test "integration: configuration parameters work across scripts" {
    # Test verbose mode works on all scripts
    run /workspace/db-backup-restore --verbose version
    assert_success

    run /workspace/db-copy --verbose version
    assert_success

    run /workspace/db-user-manager --verbose version
    assert_success
}

# Test install/uninstall workflow
@test "integration: install all scripts and verify functionality" {
    # Install all scripts
    HOME="$BATS_TMPDIR/test_home" run /workspace/db-backup-restore install
    assert_success

    HOME="$BATS_TMPDIR/test_home" run /workspace/db-copy install
    assert_success

    HOME="$BATS_TMPDIR/test_home" run /workspace/db-user-manager install
    assert_success

    # Verify all installed scripts work
    run "$BATS_TMPDIR/test_home/.local/bin/db-backup-restore" version
    assert_success

    run "$BATS_TMPDIR/test_home/.local/bin/db-copy" version
    assert_success

    run "$BATS_TMPDIR/test_home/.local/bin/db-user-manager" version
    assert_success

    # Uninstall all scripts
    HOME="$BATS_TMPDIR/test_home" run /workspace/db-backup-restore uninstall
    assert_success

    HOME="$BATS_TMPDIR/test_home" run /workspace/db-copy uninstall
    assert_success

    HOME="$BATS_TMPDIR/test_home" run /workspace/db-user-manager uninstall
    assert_success

    # Verify scripts are removed
    [ ! -f "$BATS_TMPDIR/test_home/.local/bin/db-backup-restore" ]
    [ ! -f "$BATS_TMPDIR/test_home/.local/bin/db-copy" ]
    [ ! -f "$BATS_TMPDIR/test_home/.local/bin/db-user-manager" ]
}

# Test script dependencies and prerequisites
@test "integration: all scripts handle missing dependencies gracefully" {
    # Test with minimal PATH
    export PATH="/bin:/usr/bin"

    # Scripts should either work or give helpful error messages
    run /workspace/db-backup-restore version
    assert_success || assert_output --partial "required" || assert_output --partial "install"

    run /workspace/db-copy version
    assert_success || assert_output --partial "required" || assert_output --partial "install"

    run /workspace/db-user-manager version
    assert_success || assert_output --partial "required" || assert_output --partial "install"
}
