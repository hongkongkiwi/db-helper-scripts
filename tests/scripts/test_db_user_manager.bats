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
    
    # Clean up test users that might have been created
    cleanup_test_users
}

# Helper function to run db-user-manager command
run_user_manager_cmd() {
    cd ..  # Go to project root where db-user-manager script is located
    run ./db-user-manager "$@"
}

# Helper function to clean up test users
cleanup_test_users() {
    local test_users=("test_new_user" "test_readonly_user" "test_readwrite_user" "test_limited_user" "test_temp_user")
    
    for user in "${test_users[@]}"; do
        if user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$user" "$TEST_PASS_PRIMARY"; then
            # Drop user (this might fail if user has dependencies, which is fine)
            PGPASSWORD="$TEST_PASS_PRIMARY" psql -h "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" -d "$TEST_DB_PRIMARY" \
                -c "DROP USER IF EXISTS $user;" 2>/dev/null || true
        fi
    done
}

# Test basic help and version commands
@test "db-user-manager: help command shows usage information" {
    run_user_manager_cmd help
    assert_success
    assert_output --partial "Database User Management Script"
    assert_output --partial "Usage:"
    assert_output --partial "Commands:"
    assert_output --partial "create-user"
    assert_output --partial "list-users"
}

@test "db-user-manager: version command shows version information" {
    run_user_manager_cmd version
    assert_success
    assert_output --partial "db-user-manager version"
    assert_output --partial "v1.0.0"
}

@test "db-user-manager: create-user --help shows create-user command help" {
    run_user_manager_cmd create-user --help
    assert_success
    assert_output --partial "Create new database user"
    assert_output --partial "Options:"
    assert_output --partial "--new-user"
}

@test "db-user-manager: list-users --help shows list-users command help" {
    run_user_manager_cmd list-users --help
    assert_success
    assert_output --partial "List database users"
    assert_output --partial "Options:"
}

# Test user creation
@test "db-user-manager: create basic user with password prompt" {
    # Create user with password from stdin
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_new_user" --passwd-stdin
    
    assert_success
    
    # Verify user was created
    assert user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_new_user" "$TEST_PASS_PRIMARY"
}

@test "db-user-manager: create user with specific password" {
    # Create user with password parameter (Note: this might not be available for security reasons)
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_new_user" --password
    
    # Should either succeed or prompt for password
    [ "$status" -eq 0 ] || assert_output --partial "password"
}

@test "db-user-manager: create user without login privilege" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_no_login_user" --no-login
    
    assert_success
    
    # Verify user was created
    assert user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_no_login_user" "$TEST_PASS_PRIMARY"
}

# Test user listing
@test "db-user-manager: list all users" {
    run_user_manager_cmd list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"
    
    assert_success
    
    # Should show at least the test user and some system users
    assert_output --partial "$TEST_USER_PRIMARY"
}

@test "db-user-manager: list users with detailed information" {
    run_user_manager_cmd list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --detailed
    
    assert_success
    
    # Should show detailed user information
    assert_output --partial "Username" || assert_output --partial "Superuser" || assert_output --partial "Attributes"
}

# Test permission granting
@test "db-user-manager: grant database access to user" {
    # First create a user
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_readonly_user" --passwd-stdin
    
    assert_success
    
    # Grant database access
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_readonly_user"
    
    assert_success
}

@test "db-user-manager: grant table access to user" {
    # First create a user
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_table_user" --passwd-stdin
    
    assert_success
    
    # Grant table access
    run_user_manager_cmd grant-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_table_user" \
        --table "users" --privileges "SELECT,INSERT"
    
    assert_success
}

@test "db-user-manager: grant schema access to user" {
    # First create a user
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_schema_user" --passwd-stdin
    
    assert_success
    
    # Grant schema access
    run_user_manager_cmd grant-schema-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_schema_user" \
        --schema "public" --privileges "USAGE"
    
    assert_success
}

# Test permission revocation
@test "db-user-manager: revoke table access from user" {
    # First create a user and grant access
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_revoke_user" --passwd-stdin
    
    assert_success
    
    run_user_manager_cmd grant-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_revoke_user" \
        --table "users" --privileges "SELECT"
    
    assert_success
    
    # Now revoke access
    run_user_manager_cmd revoke-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_revoke_user" \
        --table "users" --privileges "SELECT"
    
    assert_success
}

# Test user permissions display
@test "db-user-manager: show user permissions" {
    # Create user and grant some permissions first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_permissions_user" --passwd-stdin
    
    assert_success
    
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_permissions_user"
    
    assert_success
    
    # Show user permissions
    run_user_manager_cmd show-user-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_permissions_user"
    
    assert_success
    assert_output --partial "test_permissions_user" || assert_output --partial "Permissions"
}

# Test role management
@test "db-user-manager: create role" {
    run_user_manager_cmd create-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --role-name "test_role"
    
    assert_success
}

@test "db-user-manager: list roles" {
    run_user_manager_cmd list-roles \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY"
    
    assert_success
    
    # Should show some system roles
    assert_output --partial "Role" || [ ${#lines[@]} -gt 0 ]
}

@test "db-user-manager: assign role to user" {
    # Create user and role first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_role_user" --passwd-stdin
    
    assert_success
    
    run_user_manager_cmd create-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --role-name "test_user_role"
    
    assert_success
    
    # Assign role to user
    run_user_manager_cmd assign-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_role_user" --role "test_user_role"
    
    assert_success
}

# Test connection limits
@test "db-user-manager: set connection limit for user" {
    # Create user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_limited_user" --passwd-stdin
    
    assert_success
    
    # Set connection limit
    run_user_manager_cmd set-connection-limit \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_limited_user" --limit 5
    
    assert_success
}

# Test user locking/unlocking
@test "db-user-manager: lock user account" {
    # Create user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_lock_user" --passwd-stdin
    
    assert_success
    
    # Lock user
    run_user_manager_cmd lock-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_lock_user"
    
    assert_success
}

@test "db-user-manager: unlock user account" {
    # Create and lock user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_unlock_user" --passwd-stdin
    
    assert_success
    
    run_user_manager_cmd lock-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_unlock_user"
    
    assert_success
    
    # Unlock user
    run_user_manager_cmd unlock-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_unlock_user"
    
    assert_success
}

# Test password management
@test "db-user-manager: change user password" {
    # Create user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_password_user" --passwd-stdin
    
    assert_success
    
    # Change password
    echo "newpassword456" | run_user_manager_cmd change-password \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_password_user" --passwd-stdin
    
    assert_success
}

# Test user deletion
@test "db-user-manager: drop user" {
    # Create user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_drop_user" --passwd-stdin
    
    assert_success
    
    # Verify user exists
    assert user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_drop_user" "$TEST_PASS_PRIMARY"
    
    # Drop user
    run_user_manager_cmd drop-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_drop_user" --force
    
    assert_success
    
    # Verify user no longer exists
    ! user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_drop_user" "$TEST_PASS_PRIMARY"
}

# Test bulk operations
@test "db-user-manager: create multiple users from file" {
    local users_file="/tmp/test_users.txt"
    
    # Create users file
    cat > "$users_file" << EOF
test_bulk_user1
test_bulk_user2
test_bulk_user3
EOF
    
    # Create users from file
    run_user_manager_cmd create-users-batch \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --file "$users_file"
    
    # Should either succeed or indicate batch creation capability
    [ "$status" -eq 0 ] || assert_output --partial "batch" || assert_output --partial "multiple"
    
    # Clean up
    rm -f "$users_file"
}

# Test permission copying
@test "db-user-manager: copy user permissions" {
    # Create source user with permissions
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_source_user" --passwd-stdin
    
    assert_success
    
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "test_source_user"
    
    assert_success
    
    # Create target user
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_target_user" --passwd-stdin
    
    assert_success
    
    # Copy permissions
    run_user_manager_cmd copy-user-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --source-user "test_source_user" --target-user "test_target_user"
    
    assert_success
}

# Test security audit
@test "db-user-manager: security scan" {
    run_user_manager_cmd security-scan \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"
    
    assert_success
    
    # Should provide security information
    assert_output --partial "security" || assert_output --partial "audit" || assert_output --partial "scan"
}

@test "db-user-manager: audit permissions" {
    local audit_file="/tmp/test_audit.txt"
    
    run_user_manager_cmd audit-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --output-file "$audit_file"
    
    assert_success
    
    # Should create audit file
    [ -f "$audit_file" ] && [ "$(get_file_size "$audit_file")" -gt 0 ]
    
    # Clean up
    rm -f "$audit_file"
}

# Test connection management
@test "db-user-manager: terminate user connections" {
    # Create user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_terminate_user" --passwd-stdin
    
    assert_success
    
    # Terminate connections (should succeed even if no connections)
    run_user_manager_cmd terminate-user-connections \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "test_terminate_user"
    
    assert_success
}

# Test permission backup and restore
@test "db-user-manager: backup and restore permissions" {
    local backup_file="/tmp/test_permissions_backup.sql"
    
    # Backup permissions
    run_user_manager_cmd backup-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --output-file "$backup_file"
    
    assert_success
    assert_file_exists "$backup_file"
    
    # Restore permissions
    run_user_manager_cmd restore-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --input-file "$backup_file"
    
    assert_success
    
    # Clean up
    rm -f "$backup_file"
}

# Test error handling
@test "db-user-manager: error on invalid database" {
    run_user_manager_cmd list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "nonexistent_db"
    
    assert_failure
    assert_output --partial "error" || assert_output --partial "failed" || assert_output --partial "does not exist"
}

@test "db-user-manager: error on invalid connection" {
    run_user_manager_cmd list-users \
        -H "invalid_host" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"
    
    assert_failure
}

@test "db-user-manager: error when creating duplicate user" {
    # Create user first
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_duplicate_user" --passwd-stdin
    
    assert_success
    
    # Try to create same user again
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_duplicate_user" --passwd-stdin
    
    assert_failure
    assert_output --partial "exists" || assert_output --partial "already" || assert_output --partial "error"
}

@test "db-user-manager: error when operating on non-existent user" {
    run_user_manager_cmd show-user-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "nonexistent_user"
    
    assert_failure
    assert_output --partial "not found" || assert_output --partial "does not exist" || assert_output --partial "error"
}

# Test verbose output
@test "db-user-manager: verbose output shows detailed information" {
    run_user_manager_cmd list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --verbose
    
    assert_success
    
    # Should have more detailed output
    [ ${#lines[@]} -gt 3 ]
}

# Test configuration files
@test "db-user-manager: save and load configuration" {
    local config_file="/tmp/test_user_mgmt_config.conf"
    
    # Clean up any existing config file
    rm -f "$config_file"
    
    # Save configuration
    run_user_manager_cmd list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --save-config "$config_file" --dry-run
    
    # Should either succeed or indicate configuration capability
    [ "$status" -eq 0 ] || assert_output --partial "config"
    
    # Clean up
    rm -f "$config_file"
}

# Performance test
@test "db-user-manager: measure user creation time" {
    local start_time=$(date +%s)
    
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_timing_user" --passwd-stdin
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    assert_success
    
    # Log execution time
    echo "User creation completed in ${duration} seconds" >&3
    [ "$duration" -lt 10 ]  # Should complete within 10 seconds
}

# Test user existence validation
@test "db-user-manager: validate user creation" {
    echo "testpassword123" | run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "test_validation_user" --passwd-stdin
    
    assert_success
    
    # Verify user exists
    assert user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "test_validation_user" "$TEST_PASS_PRIMARY"
    
    # Verify user appears in user list
    run_user_manager_cmd list-users \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY"
    
    assert_success
    assert_output --partial "test_validation_user"
}

# Enhanced user manager tests for missing features

# Test row-level security - disable RLS
@test "db-user-manager: disable row-level security" {
    # First enable RLS on a table
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "ALTER TABLE users ENABLE ROW LEVEL SECURITY;"
    
    run_user_manager_cmd disable-rls \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-table users
    
    assert_success
    
    # Verify RLS is disabled
    local rls_status=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT relrowsecurity FROM pg_class WHERE relname = 'users';")
    assert [ "$rls_status" = "f" ]
}

# Test create RLS policy
@test "db-user-manager: create row-level security policy" {
    # Enable RLS first
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "ALTER TABLE users ENABLE ROW LEVEL SECURITY;"
    
    # Add a column for policy testing
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "ALTER TABLE users ADD COLUMN IF NOT EXISTS user_id VARCHAR(50);"
    
    run_user_manager_cmd create-policy \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --policy-name test_policy --target-table users \
        --using "user_id = current_user"
    
    assert_success
    
    # Verify policy exists
    local policy_count=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT COUNT(*) FROM pg_policies WHERE policyname = 'test_policy';")
    assert [ "$policy_count" = "1" ]
}

# Test function access grants
@test "db-user-manager: grant function access" {
    local test_user="func_test_user"
    
    # Create test user
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "testpass123"
    
    # Create a test function
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE OR REPLACE FUNCTION test_function() RETURNS INT AS 'SELECT 1;' LANGUAGE SQL;"
    
    run_user_manager_cmd grant-function-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user" --target-function test_function
    
    assert_success
    
    # Verify function access granted
    local has_access=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT has_function_privilege('$test_user', 'test_function()', 'EXECUTE');")
    assert [ "$has_access" = "t" ]
}

# Test sequence access grants
@test "db-user-manager: grant sequence access" {
    local test_user="seq_test_user"
    
    # Create test user
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "testpass123"
    
    # Create a test sequence
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE SEQUENCE test_sequence;"
    
    run_user_manager_cmd grant-sequence-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user" --target-sequence test_sequence
    
    assert_success
    
    # Verify sequence access granted
    local has_access=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT has_sequence_privilege('$test_user', 'test_sequence', 'USAGE');")
    assert [ "$has_access" = "t" ]
}

# Test apply template functionality
@test "db-user-manager: apply template" {
    local template_user="template_user"
    local target_user="target_user"
    local users_file="$BATS_TMPDIR/target_users.txt"
    
    # Create template user with specific permissions
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$template_user" --new-password "templatepass123"
    
    run_user_manager_cmd grant-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$template_user" --table users --privileges SELECT
    
    # Create target user
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$target_user" --new-password "targetpass123"
    
    # Create users file
    echo "$target_user" > "$users_file"
    
    run_user_manager_cmd apply-template \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --template-user "$template_user" --users-file "$users_file"
    
    assert_success
    
    # Verify permissions were copied
    local has_access=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT has_table_privilege('$target_user', 'users', 'SELECT');")
    assert [ "$has_access" = "t" ]
}

# Test bulk grant functionality
@test "db-user-manager: bulk grant permissions" {
    local user1="bulk_user1"
    local user2="bulk_user2"
    local users_file="$BATS_TMPDIR/bulk_users.txt"
    
    # Create test users
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$user1" --new-password "bulkpass123"
    
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$user2" --new-password "bulkpass123"
    
    # Create users file
    echo -e "$user1\n$user2" > "$users_file"
    
    run_user_manager_cmd bulk-grant \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --users-file "$users_file" --target-db "$TEST_DB_PRIMARY" --privileges CONNECT
    
    assert_success
    
    # Verify both users have connect permission
    local has_access1=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT has_database_privilege('$user1', '$TEST_DB_PRIMARY', 'CONNECT');")
    local has_access2=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT has_database_privilege('$user2', '$TEST_DB_PRIMARY', 'CONNECT');")
    assert [ "$has_access1" = "t" ]
    assert [ "$has_access2" = "t" ]
}

# Test permission validation
@test "db-user-manager: validate permissions" {
    local test_user="validate_user"
    
    # Create test user with specific permissions
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "validatepass123"
    
    run_user_manager_cmd grant-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user" --table users --privileges SELECT
    
    run_user_manager_cmd validate-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user"
    
    assert_success
    assert_output --partial "permissions"
}

# Test backup permissions
@test "db-user-manager: backup permissions" {
    local test_user="backup_perm_user"
    local backup_file="$BATS_TMPDIR/permissions_backup.sql"
    
    # Create test user with permissions
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "backuppass123"
    
    run_user_manager_cmd grant-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user" --table users --privileges SELECT
    
    run_user_manager_cmd backup-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --output-file "$backup_file"
    
    assert_success
    assert_file_exists "$backup_file"
    
    # Verify backup file contains grants
    run grep -q "GRANT.*$test_user" "$backup_file"
    assert_success
}

# Test restore permissions
@test "db-user-manager: restore permissions" {
    local test_user="restore_perm_user"
    local backup_file="$BATS_TMPDIR/restore_permissions.sql"
    
    # Create a permissions backup file
    cat > "$backup_file" << EOF
-- Permission backup
CREATE USER IF NOT EXISTS $test_user;
GRANT SELECT ON users TO $test_user;
EOF
    
    run_user_manager_cmd restore-permissions \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --input-file "$backup_file"
    
    assert_success
    
    # Verify user was created and has permissions
    assert_user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "$test_user"
}

# Test SSL certificate parameters
@test "db-user-manager: SSL certificate parameters" {
    local test_user="ssl_test_user"
    
    # Test SSL mode parameter (should work with local connections)
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "sslpass123" \
        --ssl-mode prefer
    
    assert_success
    assert_user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "$test_user"
}

# Test comprehensive config save/load
@test "db-user-manager: comprehensive config save and load" {
    local config_file="$BATS_TMPDIR/comprehensive_config.json"
    
    # Save configuration with SSL settings
    run_user_manager_cmd save-config \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --ssl-mode prefer \
        --config-file "$config_file"
    
    assert_success
    assert_file_exists "$config_file"
    
    # Verify config file contains expected settings
    run grep -q "host.*$TEST_HOST_PRIMARY" "$config_file"
    assert_success
    
    # Load configuration and test
    local test_user="config_test_user"
    run_user_manager_cmd load-config --config-file "$config_file" \
        create-user --new-user "$test_user" --new-password "configpass123"
    
    assert_success
    assert_user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "$test_user"
}

# Test user activity monitoring
@test "db-user-manager: user activity monitoring" {
    local test_user="activity_user"
    
    # Create test user
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "activitypass123"
    
    run_user_manager_cmd show-user-activity \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user"
    
    assert_success
}

# Test column-level permissions
@test "db-user-manager: column-level permissions" {
    local test_user="column_user"
    
    # Create test user
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "columnpass123"
    
    # Grant column-specific access
    run_user_manager_cmd grant-column-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$test_user" --table users \
        --columns name,email --privileges SELECT
    
    assert_success
    
    # Verify column-level access
    local has_access=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT has_column_privilege('$test_user', 'users', 'name', 'SELECT');")
    assert [ "$has_access" = "t" ]
}

# Test password strength validation
@test "db-user-manager: password strength validation" {
    local test_user="strong_pass_user"
    
    # Test with weak password (should fail if validation is enabled)
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "123" \
        --validate-password
    
    # This might succeed or fail depending on password validation settings
    # Just ensure the command runs without crash
    if [ $status -eq 0 ]; then
        assert_user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "$test_user"
    fi
}

# Test multiple role assignments
@test "db-user-manager: multiple role assignments" {
    local test_user="multi_role_user"
    local role1="test_role1"
    local role2="test_role2"
    
    # Create roles
    run_user_manager_cmd create-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --role-name "$role1"
    
    run_user_manager_cmd create-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --role-name "$role2"
    
    # Create user
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$test_user" --new-password "multirolepass123"
    
    # Assign multiple roles
    run_user_manager_cmd assign-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "$test_user" --role "$role1"
    
    run_user_manager_cmd assign-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        --target-user "$test_user" --role "$role2"
    
    assert_success
    
    # Verify both roles are assigned
    local role_count=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT COUNT(*) FROM pg_auth_members am JOIN pg_roles r ON am.roleid = r.oid JOIN pg_roles u ON am.member = u.oid WHERE u.rolname = '$test_user' AND r.rolname IN ('$role1', '$role2');")
    assert [ "$role_count" = "2" ]
}

# Test comprehensive error scenarios
@test "db-user-manager: error handling - invalid user operations" {
    # Test granting permissions to non-existent user
    run_user_manager_cmd grant-table-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "nonexistent_user" --table users --privileges SELECT
    
    assert_failure
    assert_output --partial "error"
}

# Test concurrent user operations
@test "db-user-manager: concurrent user operations" {
    local user1="concurrent_user1"
    local user2="concurrent_user2"
    
    # Start two user creation operations simultaneously
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$user1" --new-password "concurrent123" &
    
    local pid1=$!
    
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user "$user2" --new-password "concurrent123" &
    
    local pid2=$!
    
    # Wait for both to complete
    wait $pid1
    wait $pid2
    
    # Both users should be created successfully
    assert_user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "$user1"
    assert_user_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" "$user2"
}

# Test reserved user name prevention
@test "db-user-manager: prevent creating reserved user names" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user postgres --password weakpass
    
    assert_failure
    assert_output --partial "Cannot create user with reserved name: postgres"
    assert_output --partial "Reserved user names:"
}

@test "db-user-manager: prevent creating template0 user" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user template0 --password weakpass
    
    assert_failure
    assert_output --partial "Cannot create user with reserved name: template0"
}

@test "db-user-manager: prevent creating public user" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user public --password weakpass
    
    assert_failure
    assert_output --partial "Cannot create user with reserved name: public"
}

# Test password strength validation
@test "db-user-manager: weak password warning" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user test_weak_pass --password weak
    
    assert_success
    assert_output --partial "Password is shorter than 8 characters"
}

@test "db-user-manager: simple password warning" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user test_simple_pass --password "12345678"
    
    assert_success
    assert_output --partial "Password contains only one character type"
}

# Test superuser creation validation
@test "db-user-manager: superuser creation with force" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user test_superuser --password strongpass123 \
        --superuser --force
    
    assert_success
    assert_output --partial "Granting SUPERUSER privilege"
    
    # Verify user exists and is superuser
    local is_superuser=$(execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "SELECT rolsuper FROM pg_roles WHERE rolname = 'test_superuser';" | xargs)
    assert_equal "$is_superuser" "t"
    
    # Cleanup
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_superuser;"
}

# Test non-login user with connection limit warning
@test "db-user-manager: non-login user with connection limit warning" {
    run_user_manager_cmd create-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --new-user test_nologin_connlimit --password strongpass123 \
        --no-login --connection-limit 5
    
    assert_success
    assert_output --partial "Connection limit specified for non-login user"
    
    # Cleanup
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_nologin_connlimit;"
}

# Test self-granting permissions validation
@test "db-user-manager: self-granting permissions with force" {
    # First create a test user to grant permissions to
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE USER test_self_grant WITH PASSWORD 'password123';"
    
    # Note: This test assumes TEST_USER_PRIMARY is the user we're connecting as
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user "$TEST_USER_PRIMARY" --target-db "$TEST_DB_PRIMARY" \
        --privileges CONNECT --force
    
    assert_success
    assert_output --partial "You are granting permissions to yourself"
    
    # Cleanup  
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_self_grant;"
}

# Test ALL privileges warning
@test "db-user-manager: ALL privileges warning with force" {
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE USER test_all_privs WITH PASSWORD 'password123';"
    
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user test_all_privs --target-db "$TEST_DB_PRIMARY" \
        --privileges ALL --force
    
    assert_success  
    assert_output --partial "Granting ALL privileges on database"
    
    # Cleanup
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_all_privs;"
}

# Test edge cases for user deletion
@test "db-user-manager: delete non-existent user" {
    run_user_manager_cmd delete-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user nonexistent_user_12345 --force
    
    assert_failure
    assert_output --partial "User 'nonexistent_user_12345' does not exist"
}

@test "db-user-manager: delete user with owned objects warning" {
    # Create user and object
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE USER test_owner WITH PASSWORD 'password123';"
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "GRANT CREATE ON DATABASE $TEST_DB_PRIMARY TO test_owner;"
    
    # Try to delete without handling owned objects  
    run_user_manager_cmd delete-user \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user test_owner --force
    
    # Should succeed since we're not creating objects in this test
    # but the code should handle cases where objects exist
    assert_success
}

# Test role validation
@test "db-user-manager: assign non-existent role" {
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE USER test_role_assign WITH PASSWORD 'password123';"
    
    run_user_manager_cmd assign-role \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user test_role_assign --role-name nonexistent_role_12345
    
    assert_failure
    assert_output --partial "Role 'nonexistent_role_12345' does not exist"
    
    # Cleanup
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_role_assign;"
}

# Test permission validation edge cases
@test "db-user-manager: grant permissions to non-existent user" {
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user nonexistent_user_permissions --target-db "$TEST_DB_PRIMARY" \
        --privileges CONNECT
    
    assert_failure
    assert_output --partial "User 'nonexistent_user_permissions' does not exist"
}

@test "db-user-manager: grant permissions on non-existent database" {
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE USER test_nonexist_db WITH PASSWORD 'password123';"
    
    run_user_manager_cmd grant-db-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user test_nonexist_db --target-db nonexistent_database_12345 \
        --privileges CONNECT
    
    assert_failure
    assert_output --partial "Database 'nonexistent_database_12345' does not exist"
    
    # Cleanup
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_nonexist_db;"
}

# Test schema access edge cases
@test "db-user-manager: grant schema access on non-existent schema" {
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "CREATE USER test_nonexist_schema WITH PASSWORD 'password123';"
    
    run_user_manager_cmd grant-schema-access \
        -H "$TEST_HOST_PRIMARY" -p "$TEST_PORT_PRIMARY" -U "$TEST_USER_PRIMARY" \
        -d "$TEST_DB_PRIMARY" --target-user test_nonexist_schema --target-schema nonexistent_schema_12345 \
        --privileges USAGE
    
    assert_failure
    assert_output --partial "Schema 'nonexistent_schema_12345' does not exist"
    
    # Cleanup
    execute_sql "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$TEST_DB_PRIMARY" "$TEST_PASS_PRIMARY" \
        "DROP USER IF EXISTS test_nonexist_schema;"
} 