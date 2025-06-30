#!/bin/bash
# Test setup script for database helper scripts
# This script installs bats and sets up the testing environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BATS_VERSION="1.10.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin*)    PLATFORM="macos" ;;
        Linux*)     PLATFORM="linux" ;;
        *)          PLATFORM="unknown" ;;
    esac
}

log_info "Setting up test environment for database helper scripts..."
log_info "============================================"
log_info "Database Helper Scripts Test Setup"
log_info "============================================"

# Check if we're in the right directory
if [ ! -f "$PROJECT_DIR/db-backup-restore" ] || [ ! -f "$PROJECT_DIR/db-user-manager" ] || [ ! -f "$PROJECT_DIR/db-copy" ]; then
    log_error "Could not find database helper scripts in $PROJECT_DIR"
    log_error "Please run this script from the tests directory of the db-helper-scripts project"
    exit 1
fi

detect_platform
log_info "Detected platform: $PLATFORM"

# Function to install bats via brew (macOS)
install_bats_brew() {
    log_info "Installing bats via Homebrew..."

    if ! command -v brew >/dev/null 2>&1; then
        log_error "Homebrew not found. Please install Homebrew first:"
        log_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi

    # Install bats-core
    if ! brew list bats-core >/dev/null 2>&1; then
        brew install bats-core
    else
        log_info "bats-core already installed via brew"
    fi

    # Also install GNU tools for better cross-platform compatibility
    if ! brew list coreutils >/dev/null 2>&1; then
        log_info "Installing GNU coreutils for better compatibility..."
        brew install coreutils
    fi

    log_success "bats installed via Homebrew"
    return 0
}

# Function to install bats via package manager (Linux)
install_bats_package_manager() {
    log_info "Installing bats via package manager..."

    if command -v apt-get >/dev/null 2>&1; then
        # Ubuntu/Debian
        if ! dpkg -l | grep -q bats; then
            sudo apt-get update
            sudo apt-get install -y bats
        else
            log_info "bats already installed via apt"
        fi
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS
        if ! rpm -q bats >/dev/null 2>&1; then
            sudo yum install -y bats
        else
            log_info "bats already installed via yum"
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        if ! rpm -q bats >/dev/null 2>&1; then
            sudo dnf install -y bats
        else
            log_info "bats already installed via dnf"
        fi
    else
        log_warning "Package manager not recognized, falling back to source installation"
        return 1
    fi

    log_success "bats installed via package manager"
    return 0
}

# Function to install bats from source (fallback)
install_bats_source() {
    local bats_dir="/tmp/bats-core"
    local install_dir="/usr/local"

    log_info "Installing bats-core from source..."

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
        log_info "Installing bats requires sudo privileges..."
        sudo ./install.sh "$install_dir"
    fi

    # Clean up
    cd - >/dev/null
    rm -rf "$bats_dir"

    log_success "bats-core installed from source"
}

# Function to install bats with platform-specific method
install_bats() {
    # Check if bats is already installed
    if command -v bats >/dev/null 2>&1; then
        log_success "bats is already installed: $(bats --version)"
        return 0
    fi

    case "$PLATFORM" in
        macos)
            if install_bats_brew; then
                return 0
            else
                log_warning "Brew installation failed, trying source installation"
                install_bats_source
            fi
            ;;
        linux)
            if install_bats_package_manager; then
                return 0
            else
                log_warning "Package manager installation failed, trying source installation"
                install_bats_source
            fi
            ;;
        *)
            log_warning "Unknown platform, trying source installation"
            install_bats_source
            ;;
    esac
}

# Function to install bats helper libraries
install_bats_helpers() {
    local bats_helpers_dir="$SCRIPT_DIR/bats-helpers"

    log_info "Installing bats helper libraries..."

    mkdir -p "$bats_helpers_dir"

    # Install bats-support
    if [ ! -d "$bats_helpers_dir/bats-support" ]; then
        git clone https://github.com/bats-core/bats-support.git "$bats_helpers_dir/bats-support"
    else
        log_info "bats-support already installed"
    fi

    # Install bats-assert
    if [ ! -d "$bats_helpers_dir/bats-assert" ]; then
        git clone https://github.com/bats-core/bats-assert.git "$bats_helpers_dir/bats-assert"
    else
        log_info "bats-assert already installed"
    fi

    # Install bats-file
    if [ ! -d "$bats_helpers_dir/bats-file" ]; then
        git clone https://github.com/bats-core/bats-file.git "$bats_helpers_dir/bats-file"
    else
        log_info "bats-file already installed"
    fi

    log_success "bats helper libraries installed"
}

# Function to check Docker installation
check_docker() {
    log_info "Checking Docker installation..."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        log_error "Please install Docker to run the test environment"
        log_error "  macOS: brew install --cask docker"
        log_error "  Linux: Follow instructions at https://docs.docker.com/engine/install/"
        exit 1
    fi

    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not installed or not in PATH"
        log_error "Please install Docker Compose"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        log_error "Please start Docker daemon before running tests"
        exit 1
    fi

    log_success "Docker is installed and running"
}

# Function to check PostgreSQL client tools
check_pg_tools() {
    log_info "Checking PostgreSQL client tools..."

    local missing_tools=()

    for tool in psql pg_dump pg_restore createdb dropdb; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing PostgreSQL client tools: ${missing_tools[*]}"
        log_error "Please install PostgreSQL client tools:"
        case "$PLATFORM" in
            macos)
                log_error "  macOS: brew install postgresql"
                ;;
            linux)
                log_error "  Ubuntu/Debian: sudo apt-get install postgresql-client"
                log_error "  RHEL/CentOS: sudo yum install postgresql"
                log_error "  Fedora: sudo dnf install postgresql"
                ;;
        esac
        exit 1
    fi

    log_success "PostgreSQL client tools are installed"
}

# Function to make scripts executable
make_scripts_executable() {
    log_info "Making database helper scripts executable..."

    chmod +x "$PROJECT_DIR/db-backup-restore"
    chmod +x "$PROJECT_DIR/db-user-manager"
    chmod +x "$PROJECT_DIR/db-copy"
    chmod +x "$PROJECT_DIR/run-tests"

    # Make test files executable
    find "$SCRIPT_DIR/scripts" -name "*.bats" -exec chmod +x {} \;

    log_success "Scripts are now executable"
}

# Function to create test directories
create_test_directories() {
    log_info "Creating test directories..."

    mkdir -p "$SCRIPT_DIR/tmp"
    mkdir -p "$SCRIPT_DIR/reports"
    mkdir -p "$SCRIPT_DIR/logs"

    log_success "Test directories created"
}

# Function to validate test environment
validate_test_environment() {
    log_info "Validating test environment..."

    # Check if test fixture exists
    if [ ! -f "$SCRIPT_DIR/fixtures/01-init-test-data.sql" ]; then
        log_warning "Test fixtures not found. Tests may fail."
    fi

    # Check if helper functions exist
    if [ ! -f "$SCRIPT_DIR/helpers/test_helpers.bash" ]; then
        log_error "Test helper functions not found"
        exit 1
    fi

    # Check if Docker Compose file exists
    if [ ! -f "$PROJECT_DIR/docker-compose.test.yml" ]; then
        log_error "Docker Compose test configuration not found"
        exit 1
    fi

    log_success "Test environment validation complete"
}

# Function to test the installation
test_installation() {
    log_info "Testing installation..."

    # Test bats
    if command -v bats >/dev/null 2>&1; then
        local bats_version=$(bats --version)
        log_success "bats is working: $bats_version"
    else
        log_error "bats installation failed"
        exit 1
    fi

    # Test basic Docker functionality
    if docker ps >/dev/null 2>&1; then
        log_success "Docker is working"
    else
        log_error "Docker test failed"
        exit 1
    fi

    log_success "All installations tested successfully"
}

# Function to show usage instructions
show_usage() {
    echo
    log_info "============================================"
    log_info "Setup Complete!"
    log_info "============================================"
    echo
    log_info "You can now run tests using:"
    log_info "  ./run-tests                    # Run all tests"
    log_info "  ./run-tests --verbose          # Run with verbose output"
    log_info "  ./run-tests --test backup      # Run specific test suite"
    echo
    log_info "For Docker-based testing (no local dependencies):"
    log_info "  ./run-tests --docker           # Run tests in Docker container"
    echo
    log_info "For more options:"
    log_info "  ./run-tests --help"
    echo
}

# Main execution
main() {
    check_docker
    check_pg_tools
    install_bats
    install_bats_helpers
    make_scripts_executable
    create_test_directories
    validate_test_environment
    test_installation
    show_usage
}

main "$@"
