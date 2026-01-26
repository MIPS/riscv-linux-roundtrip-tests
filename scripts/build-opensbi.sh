#!/bin/bash
# Build OpenSBI fw_payload.bin for RISC-V testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --cpu <name> --payload <Image> [--output <path>]

Build OpenSBI fw_payload.bin with embedded Linux kernel Image.

Options:
    --cpu <name>          CPU name (e.g., p8700)
    --payload <path>      Path to Linux kernel Image
    --opensbi-src <path>  Path to OpenSBI source tree (default: \$OPENSBI_SRC)
    --output <path>       Output directory (default: results/)
    --jobs <N>            Number of parallel jobs (default: nproc)
    --help                Show this help

Environment:
    OPENSBI_SRC           Path to OpenSBI source tree (required)
    CROSS_COMPILE         Cross compiler prefix (required)
    TOOLCHAIN_PATH        Path to toolchain bin directory (optional)

Example:
    $(basename "$0") --cpu p8700 --payload results/Image-p8700
EOF
}

# Parse arguments
CPU_ARG=""
PAYLOAD=""
OPENSBI_SRC_ARG=""
OUTPUT_DIR=""
JOBS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            CPU_ARG="$2"
            shift 2
            ;;
        --payload)
            PAYLOAD="$2"
            shift 2
            ;;
        --opensbi-src)
            OPENSBI_SRC_ARG="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --jobs)
            JOBS="$2"
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

if [[ -z "$PAYLOAD" ]]; then
    log_error "Missing required argument: --payload"
    usage
    exit 1
fi

# Load CPU configuration
load_cpu_config "$CPU_ARG"

# Set OpenSBI source - command line arg takes precedence over env var
if [[ -n "$OPENSBI_SRC_ARG" ]]; then
    OPENSBI_SRC="$OPENSBI_SRC_ARG"
elif [[ -z "${OPENSBI_SRC:-}" ]]; then
    die "OPENSBI_SRC environment variable is not set. Set it or use --opensbi-src option."
fi

# Set other defaults
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/results}"
JOBS="${JOBS:-$(nproc)}"

# Validate OpenSBI source exists
if [[ ! -d "$OPENSBI_SRC" ]]; then
    die "OpenSBI source directory not found: $OPENSBI_SRC"
fi

if [[ ! -f "$OPENSBI_SRC/Makefile" ]]; then
    die "Not a valid OpenSBI source tree: $OPENSBI_SRC"
fi

# Validate payload exists
if [[ ! -f "$PAYLOAD" ]]; then
    die "Payload not found: $PAYLOAD"
fi

# Get absolute path to payload
PAYLOAD="$(cd "$(dirname "$PAYLOAD")" && pwd)/$(basename "$PAYLOAD")"

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

# Build OpenSBI
log_info "Building OpenSBI fw_payload.bin..."
log_info "  Source: $OPENSBI_SRC"
log_info "  Payload: $PAYLOAD"
log_info "  CROSS_COMPILE: $CROSS_COMPILE"
log_info "  Jobs: $JOBS"

cd "$OPENSBI_SRC"

# Clean previous build
make CROSS_COMPILE="$CROSS_COMPILE" PLATFORM=generic clean

# Build fw_payload.bin
make CROSS_COMPILE="$CROSS_COMPILE" \
     PLATFORM=generic \
     FW_PAYLOAD_PATH="$PAYLOAD" \
     -j"$JOBS"

# Find the built fw_payload.bin
FW_PAYLOAD_SRC="$OPENSBI_SRC/build/platform/generic/firmware/fw_payload.bin"
if [[ ! -f "$FW_PAYLOAD_SRC" ]]; then
    die "Build failed: fw_payload.bin not found at $FW_PAYLOAD_SRC"
fi

# Copy to output
FW_PAYLOAD_DST="${OUTPUT_DIR}/fw_payload-${CPU_NAME}.bin"
cp "$FW_PAYLOAD_SRC" "$FW_PAYLOAD_DST"

log_success "OpenSBI built successfully"
log_info "fw_payload.bin: $FW_PAYLOAD_DST"
ls -lh "$FW_PAYLOAD_DST"
