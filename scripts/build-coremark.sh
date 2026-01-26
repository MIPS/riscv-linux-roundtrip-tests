#!/bin/bash
# Build CoreMark benchmark for RISC-V testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --cpu <name> [--output <path>]

Build CoreMark benchmark as a static binary for RISC-V.

Options:
    --cpu <name>          CPU name (e.g., p8700)
    --output <path>       Output directory (default: results/)
    --coremark-src <path> Path to CoreMark source (default: downloads/coremark)
    --help                Show this help

Environment:
    CROSS_COMPILE         Cross compiler prefix (required)
    TOOLCHAIN_PATH        Path to toolchain bin directory (optional)

Example:
    $(basename "$0") --cpu p8700
EOF
}

COREMARK_REPO="https://github.com/eembc/coremark.git"

# Parse arguments
CPU_ARG=""
OUTPUT_DIR=""
COREMARK_SRC=""

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
        --coremark-src)
            COREMARK_SRC="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$CPU_ARG" ]]; then
    log_error "Missing required argument: --cpu"
    usage
    exit 1
fi

# Load CPU configuration
load_cpu_config "$CPU_ARG"

# Set defaults
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/results}"
COREMARK_SRC="${COREMARK_SRC:-${PROJECT_ROOT}/downloads/coremark}"

# Clone CoreMark if not present
if [[ ! -d "$COREMARK_SRC" ]]; then
    log_info "Cloning CoreMark repository..."
    ensure_dir "$(dirname "$COREMARK_SRC")"
    git clone "$COREMARK_REPO" "$COREMARK_SRC"
fi

if [[ ! -f "$COREMARK_SRC/coremark.h" ]]; then
    die "Invalid CoreMark source: $COREMARK_SRC"
fi

# Require CROSS_COMPILE
require_env "CROSS_COMPILE" "Cross compiler prefix (e.g., riscv64-linux-gnu-)"

# Verify cross compiler exists
if ! command -v "${CROSS_COMPILE}gcc" &>/dev/null; then
    die "Cross compiler not found: ${CROSS_COMPILE}gcc"
fi

log_info "Cross compiler: ${CROSS_COMPILE}gcc"
"${CROSS_COMPILE}gcc" --version | head -1

# Ensure output directory exists
ensure_dir "$OUTPUT_DIR"

# Build CoreMark
log_info "Building CoreMark..."
log_info "  Source: $COREMARK_SRC"
log_info "  CROSS_COMPILE: $CROSS_COMPILE"

cd "$COREMARK_SRC"

# Clean previous build
make clean 2>/dev/null || true

# Build static binary
# CoreMark uses PORT_DIR to specify the platform
# Use the linux port with our cross compiler
make PORT_DIR=linux \
     CC="${CROSS_COMPILE}gcc" \
     XCFLAGS="-static" \
     link

# The output binary is named coremark.exe
COREMARK_BIN="$COREMARK_SRC/coremark.exe"
if [[ ! -f "$COREMARK_BIN" ]]; then
    die "Build failed: coremark.exe not found"
fi

# Verify it's statically linked
if ! file "$COREMARK_BIN" | grep -q "statically linked"; then
    log_warn "CoreMark may not be statically linked"
fi

# Copy to output
COREMARK_DST="${OUTPUT_DIR}/coremark-${CPU_NAME}.exe"
cp "$COREMARK_BIN" "$COREMARK_DST"

log_success "CoreMark built successfully"
log_info "Binary: $COREMARK_DST"
ls -lh "$COREMARK_DST"
file "$COREMARK_DST"
