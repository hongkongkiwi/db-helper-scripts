#!/bin/bash
# Test helpers for database helper scripts testing
# This file contains common functions used across all test files

# Test configuration
export TEST_DB_PRIMARY="testdb"
export TEST_USER_PRIMARY="testuser"
export TEST_PASS_PRIMARY="testpass"
export TEST_HOST_PRIMARY="localhost"
export TEST_PORT_PRIMARY="5432"

export TEST_DB_SECONDARY="testdb2"
export TEST_USER_SECONDARY="testuser2"
export TEST_PASS_SECONDARY="testpass2"
export TEST_HOST_SECONDARY="localhost"
export TEST_PORT_SECONDARY="5433"

export TEST_BACKUP_DIR="/tmp/test_backups"
export TEST_TEMP_DIR="/tmp/db_script_tests"

# Test database connection strings
export PRIMARY_CONN="postgresql://${TEST_USER_PRIMARY}:${TEST_PASS_PRIMARY}@${TEST_HOST_PRIMARY}:${TEST_PORT_PRIMARY}/${TEST_DB_PRIMARY}"
export SECONDARY_CONN="postgresql://${TEST_USER_SECONDARY}:${TEST_PASS_SECONDARY}@${TEST_HOST_SECONDARY}:${TEST_PORT_SECONDARY}/${TEST_DB_SECONDARY}"

# Color output for test results
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m' # No Color

# Test setup functions
setup_test_environment() {
    echo "Setting up test environment..."

    # Create test directories
    mkdir -p "${TEST_BACKUP_DIR}"
    mkdir -p "${TEST_TEMP_DIR}"

    # Set permissions
    chmod 700 "${TEST_BACKUP_DIR}"
    chmod 700 "${TEST_TEMP_DIR}"

    # Wait for databases to be ready
    wait_for_database "${TEST_HOST_PRIMARY}" "${TEST_PORT_PRIMARY}" "${TEST_USER_PRIMARY}" "${TEST_DB_PRIMARY}"
    wait_for_database "${TEST_HOST_SECONDARY}" "${TEST_PORT_SECONDARY}" "${TEST_USER_SECONDARY}" "${TEST_DB_SECONDARY}"

    echo "Test environment setup complete"
}

teardown_test_environment() {
    echo "Cleaning up test environment..."

    # Clean up test directories
    rm -rf "${TEST_BACKUP_DIR}"
    rm -rf "${TEST_TEMP_DIR}"

    # Clean up any test databases that might have been created
    cleanup_test_databases

    echo "Test environment cleanup complete"
}

# Database utility functions
wait_for_database() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local max_attempts=30
    local attempt=1

    echo "Waiting for database ${dbname} on ${host}:${port}..."

    while [ $attempt -le $max_attempts ]; do
        if PGPASSWORD="${TEST_PASS_PRIMARY}" psql -h "$host" -p "$port" -U "$user" -d "$dbname" -c "SELECT 1;" >/dev/null 2>&1; then
            echo "Database ${dbname} is ready!"
            return 0
        fi

        echo "Attempt $attempt/$max_attempts failed, waiting..."
        sleep 2
        ((attempt++))
    done

    echo "Database ${dbname} failed to become ready after $max_attempts attempts"
    return 1
}

# Database connection testing
test_db_connection() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"

    PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "$dbname" -c "SELECT 1;" >/dev/null 2>&1
}

# Database query functions
execute_sql() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local sql="$6"

    PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "$dbname" -t -A -c "$sql" 2>/dev/null
}

get_table_count() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local table="$6"

    execute_sql "$host" "$port" "$user" "$dbname" "$password" "SELECT COUNT(*) FROM $table;"
}

get_row_count() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local table="$6"

    get_table_count "$host" "$port" "$user" "$dbname" "$password" "$table"
}

database_exists() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"

    local result=$(PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "postgres" -t -A -c "SELECT 1 FROM pg_database WHERE datname='$dbname';" 2>/dev/null)
    [ "$result" = "1" ]
}

user_exists() {
    local host="$1"
    local port="$2"
    local user="$3"
    local target_user="$4"
    local password="$5"

    local result=$(PGPASSWORD="$password" psql -h "$host" -p "$port" -U "$user" -d "postgres" -t -A -c "SELECT 1 FROM pg_user WHERE usename='$target_user';" 2>/dev/null)
    [ "$result" = "1" ]
}

table_exists() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local table="$6"

    local result=$(execute_sql "$host" "$port" "$user" "$dbname" "$password" "SELECT 1 FROM information_schema.tables WHERE table_name='$table' AND table_schema='public';")
    [ "$result" = "1" ]
}

schema_exists() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local schema="$6"

    local result=$(execute_sql "$host" "$port" "$user" "$dbname" "$password" "SELECT 1 FROM information_schema.schemata WHERE schema_name='$schema';")
    [ "$result" = "1" ]
}

# Test database management
create_test_database() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"

    PGPASSWORD="$password" createdb -h "$host" -p "$port" -U "$user" "$dbname" 2>/dev/null
}

drop_test_database() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"

    PGPASSWORD="$password" dropdb -h "$host" -p "$port" -U "$user" "$dbname" 2>/dev/null
}

cleanup_test_databases() {
    # List of potential test databases to clean up
    local test_dbs=("test_copy_target" "test_backup_restore" "test_user_mgmt" "temp_test_db" "validation_test_db")

    for db in "${test_dbs[@]}"; do
        if database_exists "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$db" "$TEST_PASS_PRIMARY"; then
            drop_test_database "$TEST_HOST_PRIMARY" "$TEST_PORT_PRIMARY" "$TEST_USER_PRIMARY" "$db" "$TEST_PASS_PRIMARY"
        fi

        if database_exists "$TEST_HOST_SECONDARY" "$TEST_PORT_SECONDARY" "$TEST_USER_SECONDARY" "$db" "$TEST_PASS_SECONDARY"; then
            drop_test_database "$TEST_HOST_SECONDARY" "$TEST_PORT_SECONDARY" "$TEST_USER_SECONDARY" "$db" "$TEST_PASS_SECONDARY"
        fi
    done
}

# File system utilities
create_test_file() {
    local filepath="$1"
    local content="${2:-test content}"

    mkdir -p "$(dirname "$filepath")"
    echo "$content" > "$filepath"
}

file_contains() {
    local filepath="$1"
    local pattern="$2"

    grep -q "$pattern" "$filepath" 2>/dev/null
}

count_lines_in_file() {
    local filepath="$1"

    if [ -f "$filepath" ]; then
        wc -l < "$filepath"
    else
        echo "0"
    fi
}

get_file_size() {
    local filepath="$1"

    if [ -f "$filepath" ]; then
        stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Test assertion helpers
assert_command_success() {
    local command="$1"
    local description="${2:-Command}"

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ${description} succeeded${NC}"
        return 0
    else
        echo -e "${RED}✗ ${description} failed${NC}"
        return 1
    fi
}

assert_command_failure() {
    local command="$1"
    local description="${2:-Command}"

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${RED}✗ ${description} should have failed but succeeded${NC}"
        return 1
    else
        echo -e "${GREEN}✓ ${description} failed as expected${NC}"
        return 0
    fi
}

assert_file_exists() {
    local filepath="$1"
    local description="${2:-File $filepath}"

    if [ -f "$filepath" ]; then
        echo -e "${GREEN}✓ ${description} exists${NC}"
        return 0
    else
        echo -e "${RED}✗ ${description} does not exist${NC}"
        return 1
    fi
}

assert_database_exists() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local description="${6:-Database $dbname}"

    if database_exists "$host" "$port" "$user" "$dbname" "$password"; then
        echo -e "${GREEN}✓ ${description} exists${NC}"
        return 0
    else
        echo -e "${RED}✗ ${description} does not exist${NC}"
        return 1
    fi
}

assert_table_exists() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local table="$6"
    local description="${7:-Table $table}"

    if table_exists "$host" "$port" "$user" "$dbname" "$password" "$table"; then
        echo -e "${GREEN}✓ ${description} exists${NC}"
        return 0
    else
        echo -e "${RED}✗ ${description} does not exist${NC}"
        return 1
    fi
}

assert_row_count() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"
    local table="$6"
    local expected_count="$7"
    local description="${8:-Table $table row count}"

    local actual_count=$(get_row_count "$host" "$port" "$user" "$dbname" "$password" "$table")

    if [ "$actual_count" = "$expected_count" ]; then
        echo -e "${GREEN}✓ ${description}: $actual_count = $expected_count${NC}"
        return 0
    else
        echo -e "${RED}✗ ${description}: $actual_count ≠ $expected_count${NC}"
        return 1
    fi
}

# Script execution helpers
run_db_backup_restore() {
    local args="$*"
    ./db-backup-restore $args
}

run_db_user_manager() {
    local args="$*"
    ./db-user-manager $args
}

run_db_copy() {
    local args="$*"
    ./db-copy $args
}

# Test data helpers
reset_test_data() {
    local host="$1"
    local port="$2"
    local user="$3"
    local dbname="$4"
    local password="$5"

    # Reset test data to known state
    execute_sql "$host" "$port" "$user" "$dbname" "$password" "
        DELETE FROM public.order_items;
        DELETE FROM public.orders;
        DELETE FROM public.users;
        DELETE FROM public.products;
        DELETE FROM test_schema.test_table;
        DELETE FROM public.temp_logs;
        DELETE FROM public.cache_data;

        -- Reset sequences
        ALTER SEQUENCE public.users_id_seq RESTART WITH 1;
        ALTER SEQUENCE public.orders_id_seq RESTART WITH 1;
        ALTER SEQUENCE public.products_id_seq RESTART WITH 1;
        ALTER SEQUENCE public.order_items_id_seq RESTART WITH 1;
        ALTER SEQUENCE test_schema.test_table_id_seq RESTART WITH 1;
        ALTER SEQUENCE public.temp_logs_id_seq RESTART WITH 1;
        ALTER SEQUENCE public.cache_data_id_seq RESTART WITH 1;
    "

    # Re-insert basic test data
    execute_sql "$host" "$port" "$user" "$dbname" "$password" "
        INSERT INTO public.users (username, email, metadata) VALUES
        ('testuser1', 'test1@example.com', '{\"role\": \"admin\"}'),
        ('testuser2', 'test2@example.com', '{\"role\": \"user\"}');

        INSERT INTO public.products (name, description, price, category, in_stock) VALUES
        ('Test Product 1', 'A test product', 19.99, 'electronics', 100),
        ('Test Product 2', 'Another test product', 29.99, 'books', 50);

        INSERT INTO test_schema.test_table (name, data) VALUES
        ('test_record_1', 'Some test data'),
        ('test_record_2', 'More test data');
    "
}

# Performance testing helpers
measure_execution_time() {
    local command="$1"
    local start_time=$(date +%s%3N)

    eval "$command"
    local exit_code=$?

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    echo "Execution time: ${duration}ms"
    return $exit_code
}

# Logging helpers
log_test_info() {
    echo -e "${YELLOW}[INFO]${NC} $*"
}

log_test_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_test_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# Utility to check if running in Docker
is_running_in_docker() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Export all functions for use in bats tests
export -f setup_test_environment
export -f teardown_test_environment
export -f wait_for_database
export -f test_db_connection
export -f execute_sql
export -f get_table_count
export -f get_row_count
export -f database_exists
export -f user_exists
export -f table_exists
export -f schema_exists
export -f create_test_database
export -f drop_test_database
export -f cleanup_test_databases
export -f create_test_file
export -f file_contains
export -f count_lines_in_file
export -f get_file_size
export -f assert_command_success
export -f assert_command_failure
export -f assert_file_exists
export -f assert_database_exists
export -f assert_table_exists
export -f assert_row_count
export -f run_db_backup_restore
export -f run_db_user_manager
export -f run_db_copy
export -f reset_test_data
export -f measure_execution_time
export -f log_test_info
export -f log_test_error
export -f log_test_success
export -f is_running_in_docker
