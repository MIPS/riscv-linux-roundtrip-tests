#!/bin/bash
# Common functions for RISC-V Linux roundtrip tests

# Exit codes
EXIT_SUCCESS=0
EXIT_BUILD_FAIL=1
EXIT_BOOT_FAIL=2
EXIT_TEST_FAIL=3
EXIT_TIMEOUT=4

# Color support
if [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && command -v tput &>/dev/null; then
    COLOR_RED=$(tput setaf 1)
    COLOR_GREEN=$(tput setaf 2)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_BLUE=$(tput setaf 4)
    COLOR_RESET=$(tput sgr0)
else
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_RESET=""
fi

# Detect project root directory
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

    # Navigate up from scripts/ or scripts/lib/ to project root
    if [[ "$(basename "$script_dir")" == "lib" ]]; then
        echo "$(dirname "$(dirname "$script_dir")")"
    else
        echo "$(dirname "$script_dir")"
    fi
}

PROJECT_ROOT="$(get_project_root)"

# Quiet mode - set COMMON_QUIET=true to suppress info/success messages
COMMON_QUIET="${COMMON_QUIET:-false}"

# Logging functions
log_info() {
    [[ "$COMMON_QUIET" == "true" ]] && return
    echo "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_warn() {
    [[ "$COMMON_QUIET" == "true" ]] && return
    echo "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    # Errors are always shown
    echo "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_success() {
    [[ "$COMMON_QUIET" == "true" ]] && return
    echo "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
}

die() {
    log_error "$@"
    exit 1
}

# Load CPU configuration
# Usage: load_cpu_config <cpu_name>
load_cpu_config() {
    local cpu_name="$1"
    local config_file="${PROJECT_ROOT}/configs/${cpu_name}.conf"

    if [[ ! -f "$config_file" ]]; then
        die "Configuration file not found: $config_file"
    fi

    # shellcheck source=/dev/null
    source "$config_file"

    log_info "Loaded configuration for CPU: $cpu_name"
}

# Run command with timeout
# Usage: run_with_timeout <timeout_seconds> <command> [args...]
run_with_timeout() {
    local timeout="$1"
    shift

    timeout --foreground "$timeout" "$@"
    local ret=$?

    if [[ $ret -eq 124 ]]; then
        log_error "Command timed out after ${timeout}s: $*"
        return $EXIT_TIMEOUT
    fi

    return $ret
}

# Check if a command exists
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        die "Required command not found: $cmd"
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Parse common arguments
# Sets: CPU_ARG, OUTPUT_DIR
parse_common_args() {
    CPU_ARG=""
    OUTPUT_DIR=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cpu)
                CPU_ARG="$2"
                shift 2
                ;;
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --help|-h)
                return 1
                ;;
            *)
                # Return remaining args
                REMAINING_ARGS=("$@")
                return 0
                ;;
        esac
    done

    return 0
}

# Environment variables for paths (must be set by user)
# Use these instead of hardcoded paths:
#   QEMU_BIN       - Path to qemu-system-riscv64 (required for boot/test)
#   CROSS_COMPILE  - Cross compiler prefix (required for building)
#   TOOLCHAIN_PATH - Path to toolchain bin directory (optional, added to PATH)
#   LINUX_SRC      - Path to Linux source tree (required for build-linux.sh)
#   OPENSBI_SRC    - Path to OpenSBI source tree (required for build-opensbi.sh)

# Add toolchain to PATH if TOOLCHAIN_PATH is set
if [[ -n "${TOOLCHAIN_PATH:-}" && -d "$TOOLCHAIN_PATH" ]]; then
    export PATH="${TOOLCHAIN_PATH}:$PATH"
fi

# Require environment check function
require_env() {
    local var_name="$1"
    local description="${2:-}"

    if [[ -z "${!var_name:-}" ]]; then
        log_error "Required environment variable $var_name is not set"
        if [[ -n "$description" ]]; then
            log_error "  $description"
        fi
        log_error ""
        log_error "Run './scripts/check-env.sh' to verify your environment setup"
        exit 1
    fi
}

# Get QEMU binary from environment or fail
get_qemu_bin() {
    if [[ -n "${QEMU_BIN:-}" ]]; then
        if [[ -x "$QEMU_BIN" ]]; then
            echo "$QEMU_BIN"
            return 0
        else
            log_error "QEMU_BIN is set but not executable: $QEMU_BIN"
            return 1
        fi
    fi

    # Fall back to system PATH
    if command -v "qemu-system-riscv64" &>/dev/null; then
        echo "qemu-system-riscv64"
        return 0
    fi

    log_error "QEMU_BIN is not set and qemu-system-riscv64 not found in PATH"
    log_error "Run './scripts/check-env.sh' to verify your environment setup"
    return 1
}

# Default QEMU binary (will fail gracefully if not found)
DEFAULT_QEMU_BIN="${QEMU_BIN:-qemu-system-riscv64}"
