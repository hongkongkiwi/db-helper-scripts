#!/bin/bash
# Test setup script for database helper scripts
# This script installs bats and sets up the testing environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BATS_VERSION="1.10.0"

echo "Setting up test environment for database helper scripts..."

# Check if we're in the right directory
if [ ! -f "$PROJECT_DIR/db-backup-restore" ] || [ ! -f "$PROJECT_DIR/db-user-manager" ] || [ ! -f "$PROJECT_DIR/db-copy" ]; then
    echo "Error: Could not find database helper scripts in $PROJECT_DIR"
    echo "Please run this script from the tests directory of the db-helper-scripts project"
    exit 1
fi

# Function to install bats on different systems
install_bats() {
    local bats_dir="/tmp/bats-core"
    local install_dir="/usr/local"

    echo "Installing bats-core..."

    # Check if bats is already installed
    if command -v bats >/dev/null 2>&1; then
        echo "bats is already installed: $(bats --version)"
        return 0
    fi

    # Remove any existing bats installation directory
    rm -rf "$bats_dir"

    # Clone bats-core
    git clone https://github.com/bats-core/bats-core.git "$bats_dir"
    cd "$bats_dir"
    git checkout "v$BATS_VERSION"

    # Install bats
    if [ "$EUID" -eq 0 ]; then
        ./install.sh "$install_dir"
    else
        echo "Installing bats requires sudo privileges..."
        sudo ./install.sh "$install_dir"
    fi

    # Clean up
    cd - >/dev/null
    rm -rf "$bats_dir"

    echo "bats-core installed successfully"
}

# Function to install bats helper libraries
install_bats_helpers() {
    local bats_helpers_dir="$SCRIPT_DIR/bats-helpers"

    echo "Installing bats helper libraries..."

    mkdir -p "$bats_helpers_dir"

    # Install bats-support
    if [ ! -d "$bats_helpers_dir/bats-support" ]; then
        git clone https://github.com/bats-core/bats-support.git "$bats_helpers_dir/bats-support"
    fi

    # Install bats-assert
    if [ ! -d "$bats_helpers_dir/bats-assert" ]; then
        git clone https://github.com/bats-core/bats-assert.git "$bats_helpers_dir/bats-assert"
    fi

    # Install bats-file
    if [ ! -d "$bats_helpers_dir/bats-file" ]; then
        git clone https://github.com/bats-core/bats-file.git "$bats_helpers_dir/bats-file"
    fi

    echo "bats helper libraries installed successfully"
}

# Function to check Docker installation
check_docker() {
    echo "Checking Docker installation..."

    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: Docker is not installed or not in PATH"
        echo "Please install Docker to run the test environment"
        exit 1
    fi

    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        echo "Error: Docker Compose is not installed or not in PATH"
        echo "Please install Docker Compose to run the test environment"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        echo "Error: Docker daemon is not running"
        echo "Please start Docker daemon before running tests"
        exit 1
    fi

    echo "Docker is installed and running"
}

# Function to check PostgreSQL client tools
check_pg_tools() {
    echo "Checking PostgreSQL client tools..."

    local missing_tools=()

    if ! command -v psql >/dev/null 2>&1; then
        missing_tools+=("psql")
    fi

    if ! command -v pg_dump >/dev/null 2>&1; then
        missing_tools+=("pg_dump")
    fi

    if ! command -v pg_restore >/dev/null 2>&1; then
        missing_tools+=("pg_restore")
    fi

    if ! command -v createdb >/dev/null 2>&1; then
        missing_tools+=("createdb")
    fi

    if ! command -v dropdb >/dev/null 2>&1; then
        missing_tools+=("dropdb")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "Error: Missing PostgreSQL client tools: ${missing_tools[*]}"
        echo "Please install PostgreSQL client tools:"
        echo "  Ubuntu/Debian: sudo apt-get install postgresql-client"
        echo "  RHEL/CentOS: sudo yum install postgresql"
        echo "  macOS: brew install postgresql"
        exit 1
    fi

    echo "PostgreSQL client tools are installed"
}

# Function to make scripts executable
make_scripts_executable() {
    echo "Making database helper scripts executable..."

    chmod +x "$PROJECT_DIR/db-backup-restore"
    chmod +x "$PROJECT_DIR/db-user-manager"
    chmod +x "$PROJECT_DIR/db-copy"

    echo "Scripts are now executable"
}

# Function to create test directories
create_test_directories() {
    echo "Creating test directories..."

    mkdir -p "$SCRIPT_DIR/tmp"
    mkdir -p "$SCRIPT_DIR/reports"
    mkdir -p "$SCRIPT_DIR/logs"

    echo "Test directories created"
}

# Function to validate test environment
validate_test_environment() {
    echo "Validating test environment..."

    # Check if test fixture exists
    if [ ! -f "$SCRIPT_DIR/fixtures/01-init-test-data.sql" ]; then
        echo "Warning: Test fixtures not found. Tests may fail."
    fi

    # Check if helper functions exist
    if [ ! -f "$SCRIPT_DIR/helpers/test_helpers.bash" ]; then
        echo "Error: Test helper functions not found"
        exit 1
    fi

    # Check if Docker Compose file exists
    if [ ! -f "$PROJECT_DIR/docker-compose.test.yml" ]; then
        echo "Error: Docker Compose test configuration not found"
        exit 1
    fi

    echo "Test environment validation complete"
}

# Function to create test runner script
create_test_runner() {
    local runner_script="$PROJECT_DIR/run-tests.sh"

    echo "Creating test runner script..."

    cat > "$runner_script" << 'EOF'
#!/bin/bash
# Test runner script for database helper scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

# Default values
RUN_SETUP=true
RUN_TEARDOWN=true
PARALLEL_JOBS=1
VERBOSE=false
SPECIFIC_TEST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-setup)
            RUN_SETUP=false
            shift
            ;;
        --no-teardown)
            RUN_TEARDOWN=false
            shift
            ;;
        --parallel)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --no-setup          Skip Docker environment setup"
            echo "  --no-teardown       Skip Docker environment cleanup"
            echo "  --parallel JOBS     Run tests in parallel (default: 1)"
            echo "  --verbose, -v       Verbose output"
            echo "  --test NAME         Run specific test file"
            echo "  --help, -h          Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "Starting database helper scripts test suite..."

# Setup Docker environment
if [ "$RUN_SETUP" = true ]; then
    echo "Setting up Docker test environment..."
    cd "$SCRIPT_DIR"
    docker-compose -f docker-compose.test.yml down -v || true
    docker-compose -f docker-compose.test.yml up -d

    # Wait for services to be ready
    echo "Waiting for PostgreSQL services to be ready..."
    sleep 15

    # Verify services are healthy
    if ! docker-compose -f docker-compose.test.yml ps | grep -q "healthy"; then
        echo "Warning: Some services may not be healthy. Checking individual service status..."
        docker-compose -f docker-compose.test.yml ps
    fi
fi

# Run tests
cd "$TESTS_DIR"

if [ -n "$SPECIFIC_TEST" ]; then
    echo "Running specific test: $SPECIFIC_TEST"
    if [ "$VERBOSE" = true ]; then
        bats --verbose "$SPECIFIC_TEST"
    else
        bats "$SPECIFIC_TEST"
    fi
else
    echo "Running all tests..."
    if [ "$VERBOSE" = true ]; then
        bats --verbose --jobs "$PARALLEL_JOBS" scripts/
    else
        bats --jobs "$PARALLEL_JOBS" scripts/
    fi
fi

# Cleanup Docker environment
if [ "$RUN_TEARDOWN" = true ]; then
    echo "Cleaning up Docker test environment..."
    cd "$SCRIPT_DIR"
    docker-compose -f docker-compose.test.yml down -v
fi

echo "Test suite completed!"
EOF

    chmod +x "$runner_script"
    echo "Test runner script created: $runner_script"
}

# Main setup function
main() {
    echo "============================================"
    echo "Database Helper Scripts Test Setup"
    echo "============================================"

    # Check system requirements
    check_docker
    check_pg_tools

    # Install testing tools
    install_bats
    install_bats_helpers

    # Setup project
    make_scripts_executable
    create_test_directories
    create_test_runner

    # Validate environment
    validate_test_environment

    echo "============================================"
    echo "Test setup completed successfully!"
    echo "============================================"
    echo ""
    echo "To run tests:"
    echo "  ./run-tests.sh                    # Run all tests"
    echo "  ./run-tests.sh --verbose          # Run with verbose output"
    echo "  ./run-tests.sh --test scripts/test_db_copy.bats  # Run specific test"
    echo "  ./run-tests.sh --parallel 4       # Run tests in parallel"
    echo ""
    echo "To run individual test files:"
    echo "  cd tests"
    echo "  bats scripts/test_db_backup_restore.bats"
    echo "  bats scripts/test_db_user_manager.bats"
    echo "  bats scripts/test_db_copy.bats"
    echo ""
    echo "Docker test environment:"
    echo "  docker-compose -f docker-compose.test.yml up    # Start test databases"
    echo "  docker-compose -f docker-compose.test.yml down  # Stop test databases"
    echo ""
    echo "For more information, see the test documentation in tests/README.md"
}

# Run main function
main "$@"
