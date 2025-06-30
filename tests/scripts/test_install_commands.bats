#!/usr/bin/env bats

# Tests for install/uninstall/update commands across all scripts

load '../bats-helpers/bats-support/load'
load '../bats-helpers/bats-assert/load'
load '../bats-helpers/bats-file/load'
load '../helpers/test_helpers.bash'

setup() {
    # Set up test environment
    export TEST_INSTALL_DIR="$BATS_TMPDIR/test_local_bin"
    export ORIGINAL_HOME="$HOME"
    export HOME="$BATS_TMPDIR/test_home"

    # Create test directories
    mkdir -p "$TEST_INSTALL_DIR"
    mkdir -p "$HOME/.local/bin"

    # Create fake github response for testing
    export GITHUB_RESPONSE='{"tag_name": "v2.1.0"}'
}

teardown() {
    # Clean up test environment
    rm -rf "$TEST_INSTALL_DIR"
    rm -rf "$HOME"
    export HOME="$ORIGINAL_HOME"

    # Clean up any test scripts that may have been installed
    rm -f "$ORIGINAL_HOME/.local/bin/db-backup-restore-test"
    rm -f "$ORIGINAL_HOME/.local/bin/db-copy-test"
    rm -f "$ORIGINAL_HOME/.local/bin/db-user-manager-test"
}

# Helper function to run script commands with test paths
run_with_test_home() {
    local script="$1"
    shift

    # Check if we're in Docker environment or local
    if [[ -f "/workspace/db-backup-restore" ]]; then
        # Docker environment
        HOME="$BATS_TMPDIR/test_home" run "$script" "$@"
    else
        # Local environment - adjust path
        local script_name=$(basename "$script")
        if [[ -f "../$script_name" ]]; then
            HOME="$BATS_TMPDIR/test_home" run "../$script_name" "$@"
        else
            skip "Script $script_name not found in test environment"
        fi
    fi
}

# Test install commands
@test "install: db-backup-restore install command" {
    run_with_test_home /workspace/db-backup-restore install

    assert_success
    assert_output --partial "Successfully installed"
    assert_output --partial ".local/bin"

    # Check that script was copied
    [ -f "$HOME/.local/bin/db-backup-restore" ]
    [ -x "$HOME/.local/bin/db-backup-restore" ]
}

@test "install: db-copy install command" {
    run_with_test_home /workspace/db-copy install

    assert_success
    assert_output --partial "Successfully installed"
    assert_output --partial ".local/bin"

    # Check that script was copied
    [ -f "$HOME/.local/bin/db-copy" ]
    [ -x "$HOME/.local/bin/db-copy" ]
}

@test "install: db-user-manager install command" {
    run_with_test_home /workspace/db-user-manager install

    assert_success
    assert_output --partial "Successfully installed"
    assert_output --partial ".local/bin"

    # Check that script was copied
    [ -f "$HOME/.local/bin/db-user-manager" ]
    [ -x "$HOME/.local/bin/db-user-manager" ]
}

# Test install creates directory if it doesn't exist
@test "install: creates install directory if missing" {
    # Remove the directory we created in setup
    rm -rf "$HOME/.local"

    run_with_test_home /workspace/db-backup-restore install

    assert_success
    [ -d "$HOME/.local/bin" ]
    [ -f "$HOME/.local/bin/db-backup-restore" ]
}

# Test install handles existing script
@test "install: overwrites existing script" {
    # First install
    run_with_test_home /workspace/db-backup-restore install
    assert_success

    # Second install should overwrite
    run_with_test_home /workspace/db-backup-restore install
    assert_success
    assert_output --partial "Successfully installed"
}

# Test uninstall commands
@test "uninstall: db-backup-restore uninstall command" {
    # Install first
    run_with_test_home /workspace/db-backup-restore install
    assert_success

    # Then uninstall
    run_with_test_home /workspace/db-backup-restore uninstall
    assert_success
    assert_output --partial "Successfully removed"

    # Check that script was removed
    [ ! -f "$HOME/.local/bin/db-backup-restore" ]
}

@test "uninstall: db-copy uninstall command" {
    # Install first
    run_with_test_home /workspace/db-copy install
    assert_success

    # Then uninstall
    run_with_test_home /workspace/db-copy uninstall
    assert_success
    assert_output --partial "Successfully removed"

    # Check that script was removed
    [ ! -f "$HOME/.local/bin/db-copy" ]
}

@test "uninstall: db-user-manager uninstall command" {
    # Install first
    run_with_test_home /workspace/db-user-manager install
    assert_success

    # Then uninstall
    run_with_test_home /workspace/db-user-manager uninstall
    assert_success
    assert_output --partial "Successfully removed"

    # Check that script was removed
    [ ! -f "$HOME/.local/bin/db-user-manager" ]
}

# Test uninstall when not installed
@test "uninstall: handles script not installed" {
    run_with_test_home /workspace/db-backup-restore uninstall

    assert_success
    assert_output --partial "is not installed"
}

# Test version commands
@test "version: db-backup-restore version command" {
    if [[ -f "/workspace/db-backup-restore" ]]; then
        run /workspace/db-backup-restore version
    else
        run ../db-backup-restore version
    fi

    assert_success
    assert_output --partial "db-backup-restore version"
    assert_output --partial "2.0.0"
}

@test "version: db-copy version command" {
    if [[ -f "/workspace/db-copy" ]]; then
        run /workspace/db-copy version
    else
        run ../db-copy version
    fi

    assert_success
    assert_output --partial "db-copy v"
    assert_output --partial "1.0.0"
}

@test "version: db-user-manager version command" {
    if [[ -f "/workspace/db-user-manager" ]]; then
        run /workspace/db-user-manager version
    else
        run ../db-user-manager version
    fi

    assert_success
    assert_output --partial "db-user-manager version"
    assert_output --partial "1.0.0"
}

# Test update commands (mock network calls)
@test "update: shows current version check" {
    # Skip network-dependent test in CI or if no network
    if [[ -z "${GITHUB_TOKEN:-}" ]] && ! curl -s github.com >/dev/null 2>&1; then
        skip "Network not available for update test"
    fi

    if [[ -f "/workspace/db-backup-restore" ]]; then
        run /workspace/db-backup-restore update
    else
        run ../db-backup-restore update
    fi

    # Should at least try to check for updates
    assert_output --partial "Checking for updates" || \
    assert_output --partial "Failed to check for updates" || \
    assert_output --partial "latest version"
}

# Test PATH warnings
@test "install: warns when PATH doesn't include .local/bin" {
    # Set PATH without .local/bin
    export PATH="/usr/bin:/bin"

    run_with_test_home /workspace/db-backup-restore install

    assert_success
    assert_output --partial "not in your PATH"
    assert_output --partial "Add it to your PATH"
}

@test "install: no PATH warning when .local/bin in PATH" {
    # Set PATH to include .local/bin
    export PATH="$HOME/.local/bin:/usr/bin:/bin"

    run_with_test_home /workspace/db-backup-restore install

    assert_success
    assert_output --partial "Successfully installed"
    # Should not contain PATH warning
    ! assert_output --partial "not in your PATH"
}

# Test error conditions
@test "install: handles permission errors gracefully" {
    # Create a read-only directory
    mkdir -p "$HOME/.local"
    chmod 444 "$HOME/.local"

    run_with_test_home /workspace/db-backup-restore install

    assert_failure
    assert_output --partial "Failed to create install directory" || \
    assert_output --partial "Permission denied"

    # Restore permissions for cleanup
    chmod 755 "$HOME/.local"
}

# Test commands work after installation
@test "install: installed script is functional" {
    # Install script
    run_with_test_home /workspace/db-backup-restore install
    assert_success

    # Test that installed script works
    run "$HOME/.local/bin/db-backup-restore" version
    assert_success
    assert_output --partial "version"
}

# Test help includes new commands
@test "help: all scripts show install/uninstall/update commands" {
    if [[ -f "/workspace/db-backup-restore" ]]; then
        run /workspace/db-backup-restore help
    else
        run ../db-backup-restore help
    fi
    assert_success
    assert_output --partial "install"
    assert_output --partial "uninstall"
    assert_output --partial "update"

    if [[ -f "/workspace/db-copy" ]]; then
        run /workspace/db-copy help
    else
        run ../db-copy help
    fi
    assert_success
    assert_output --partial "install"
    assert_output --partial "uninstall"
    assert_output --partial "update"

    if [[ -f "/workspace/db-user-manager" ]]; then
        run /workspace/db-user-manager help
    else
        run ../db-user-manager help
    fi
    assert_success
    assert_output --partial "install"
    assert_output --partial "uninstall"
    assert_output --partial "update"
}

# Test install/uninstall/update commands don't require PostgreSQL
@test "install: works without PostgreSQL installed" {
    # Temporarily hide PostgreSQL commands
    export PATH="/usr/bin:/bin"

    run_with_test_home /workspace/db-backup-restore install
    assert_success

    run_with_test_home /workspace/db-copy install
    assert_success

    run_with_test_home /workspace/db-user-manager install
    assert_success
}
