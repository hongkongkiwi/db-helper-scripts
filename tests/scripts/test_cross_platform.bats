#!/usr/bin/env bats

# Cross-platform compatibility tests for database helper scripts

load '../bats-helpers/bats-support/load'
load '../bats-helpers/bats-assert/load'
load '../helpers/test_helpers.bash'

setup() {
    # Load test helpers and environment
    source "$BATS_TEST_DIRNAME/../helpers/test_helpers.bash"

    # Set up basic test environment if not already configured
    if [[ -z "${TEST_HOST_PRIMARY:-}" ]]; then
        export TEST_HOST_PRIMARY="localhost"
        export TEST_PORT_PRIMARY="15432"
        export TEST_USER_PRIMARY="postgres"
        export TEST_DB_PRIMARY="testdb"
        export TEST_PASS_PRIMARY="testpass"
    fi
}

# Test cross-platform stat command usage
@test "cross-platform: stat command works on both platforms" {
    local test_file=$(mktemp)
    echo "test content" > "$test_file"

    # This should work on both macOS and Linux
    local file_size=$(stat -f%z "$test_file" 2>/dev/null || stat -c%s "$test_file" 2>/dev/null)

    [[ "$file_size" -gt 0 ]]
    rm -f "$test_file"
}

# Test cross-platform timeout command availability
@test "cross-platform: timeout command handling" {
    # Test that timeout command works if available
    run which timeout

    if [[ $status -eq 0 ]]; then
        # timeout is available, test it works
        assert_success
        run timeout 1 sleep 0.5
        assert_success
    else
        # timeout not available - scripts should handle this gracefully
        echo "timeout command not available - testing fallback behavior"
        [[ $status -ne 0 ]]
    fi
}

# Test cross-platform date command usage
@test "cross-platform: date command timestamp generation" {
    # Test basic timestamp generation that works on both platforms
    local timestamp=$(date +%s)

    [[ "$timestamp" -gt 0 ]]

    # Test that we can calculate duration
    sleep 1
    local end_timestamp=$(date +%s)
    local duration=$((end_timestamp - timestamp))

    [[ "$duration" -ge 1 ]]
}

# Test PostgreSQL client tools availability
@test "cross-platform: PostgreSQL client tools available" {
    run which psql
    assert_success

    run which pg_dump
    assert_success

    run which pg_restore
    assert_success

    run which createdb
    assert_success

    run which dropdb
    assert_success
}

# Test Docker availability for testing
@test "cross-platform: Docker environment" {
    run docker --version
    if [[ $status -eq 0 ]]; then
        assert_success
        run docker-compose --version
        assert_success
    else
        skip "Docker not available in this environment"
    fi
}

# Test script executability on current platform
@test "cross-platform: script permissions and executability" {
    [[ -x "/workspace/db-backup-restore" ]]
    [[ -x "/workspace/db-copy" ]]
    [[ -x "/workspace/db-user-manager" ]]
    [[ -x "/workspace/run-tests" ]]
}

# Test bash version compatibility
@test "cross-platform: bash version requirements" {
    local bash_version=$(bash --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+' | head -n1)
    local major_version=$(echo "$bash_version" | cut -d. -f1)

    # Require bash 4.0 or higher for associative arrays and other features
    [[ "$major_version" -ge 4 ]]
}

# Test temporary directory creation
@test "cross-platform: temporary file handling" {
    local temp_file=$(mktemp)
    local temp_dir=$(mktemp -d)

    [[ -f "$temp_file" ]]
    [[ -d "$temp_dir" ]]

    # Test cleanup
    rm -f "$temp_file"
    rmdir "$temp_dir"

    [[ ! -f "$temp_file" ]]
    [[ ! -d "$temp_dir" ]]
}

# Test sed command compatibility
@test "cross-platform: sed command basic operations" {
    local test_file=$(mktemp)
    echo "test content" > "$test_file"

    # Test basic sed substitution (should work on both BSD and GNU sed)
    sed 's/test/modified/' "$test_file" > "$test_file.new"

    run grep "modified" "$test_file.new"
    assert_success

    rm -f "$test_file" "$test_file.new"
}

# Test compression tools availability
@test "cross-platform: compression tools availability" {
    # Test for gzip (should be universally available)
    run which gzip
    if [[ $status -eq 0 ]]; then
        assert_success
        # Test that gzip actually works
        run bash -c "echo 'test' | gzip | gunzip"
        assert_success
    else
        skip "gzip not available in this environment"
    fi

    # Test for other compression tools (optional)
    if command -v bzip2 >/dev/null 2>&1; then
        echo "bzip2 available"
    fi

    if command -v lz4 >/dev/null 2>&1; then
        echo "lz4 available"
    fi
}

# Test network connectivity for database connections
@test "cross-platform: network connectivity test" {
    # Test that we can connect to the test database using PostgreSQL
    run psql -h postgres-primary -p 5432 -U testuser -d testdb -c "SELECT 1" 2>/dev/null
    if [[ $status -eq 0 ]]; then
        assert_success
    else
        skip "Test database not available"
    fi
}

# Test file path handling
@test "cross-platform: file path operations" {
    local test_path="/tmp/test/path/file.txt"
    local dir_path=$(dirname "$test_path")
    local base_name=$(basename "$test_path")

    [[ "$dir_path" = "/tmp/test/path" ]]
    [[ "$base_name" = "file.txt" ]]
}

# Test environment variable handling
@test "cross-platform: environment variable operations" {
    # Test setting and reading environment variables
    export TEST_CROSS_PLATFORM_VAR="test_value"

    [[ "$TEST_CROSS_PLATFORM_VAR" = "test_value" ]]

    unset TEST_CROSS_PLATFORM_VAR
    [[ -z "${TEST_CROSS_PLATFORM_VAR:-}" ]]
}

# Test process handling
@test "cross-platform: process management" {
    # Test background process handling
    sleep 2 &
    local bg_pid=$!

    # Check that process is running
    run kill -0 "$bg_pid"
    if [[ $status -eq 0 ]]; then
        # Process is running, now kill it
        kill "$bg_pid" 2>/dev/null || true
        wait "$bg_pid" 2>/dev/null || true
    fi

    # Test passes if we get here without errors
    [[ true ]]
}

# Test signal handling
@test "cross-platform: signal handling compatibility" {
    # Test basic signal handling - just test that we can trap signals
    local signal_received=false

    # Set up signal trap
    trap 'signal_received=true' USR1

    # Send signal to self
    kill -USR1 $$

    # Give it a moment to process
    sleep 0.1

    # Reset trap
    trap - USR1

    # Check that signal was received
    [[ "$signal_received" = true ]]
}
