#!/bin/bash
# Build Linux kernel for RISC-V testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --cpu <name> [--linux-src <path>] [--output <path>]

Build Linux kernel Image for the specified CPU.

Options:
    --cpu <name>          CPU name (e.g., p8700)
    --linux-src <path>    Path to Linux source tree (default: \$LINUX_SRC)
    --output <path>       Output directory for Image (default: results/)
    --defconfig <name>    Defconfig to use (default: from CPU config)
    --jobs <N>            Number of parallel jobs (default: nproc)
    --help                Show this help

Environment:
    LINUX_SRC             Path to Linux kernel source tree (required)
    CROSS_COMPILE         Cross compiler prefix (required)
    TOOLCHAIN_PATH        Path to toolchain bin directory (optional)

Example:
    $(basename "$0") --cpu p8700
    $(basename "$0") --cpu p8700 --linux-src /path/to/linux --output ./build
EOF
}

# Parse arguments
CPU_ARG=""
LINUX_SRC_ARG=""
OUTPUT_DIR=""
DEFCONFIG_ARG=""
JOBS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            CPU_ARG="$2"
            shift 2
            ;;
        --linux-src)
            LINUX_SRC_ARG="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --defconfig)
            DEFCONFIG_ARG="$2"
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

# Load CPU configuration
load_cpu_config "$CPU_ARG"

# Set Linux source - command line arg takes precedence over env var
if [[ -n "$LINUX_SRC_ARG" ]]; then
    LINUX_SRC="$LINUX_SRC_ARG"
elif [[ -z "${LINUX_SRC:-}" ]]; then
    die "LINUX_SRC environment variable is not set. Set it or use --linux-src option."
fi

# Set other defaults
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/results}"
DEFCONFIG_ARG="${DEFCONFIG_ARG:-$DEFCONFIG}"
JOBS="${JOBS:-$(nproc)}"

# Validate Linux source exists
if [[ ! -d "$LINUX_SRC" ]]; then
    die "Linux source directory not found: $LINUX_SRC"
fi

if [[ ! -f "$LINUX_SRC/Makefile" ]]; then
    die "Not a valid Linux source tree: $LINUX_SRC"
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

# Build Linux kernel
log_info "Building Linux kernel..."
log_info "  Source: $LINUX_SRC"
log_info "  ARCH: $ARCH"
log_info "  CROSS_COMPILE: $CROSS_COMPILE"
log_info "  Defconfig: $DEFCONFIG_ARG"
log_info "  Jobs: $JOBS"

cd "$LINUX_SRC"

# Configure
log_info "Running make $DEFCONFIG_ARG..."
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$DEFCONFIG_ARG"

# Build Image
log_info "Building Image..."
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" Image

# Copy Image to output
IMAGE_SRC="$LINUX_SRC/arch/$ARCH/boot/Image"
if [[ ! -f "$IMAGE_SRC" ]]; then
    die "Build failed: Image not found at $IMAGE_SRC"
fi

IMAGE_DST="${OUTPUT_DIR}/Image-${CPU_NAME}"
cp "$IMAGE_SRC" "$IMAGE_DST"

log_success "Linux kernel built successfully"
log_info "Image: $IMAGE_DST"
ls -lh "$IMAGE_DST"
