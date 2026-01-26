#!/bin/bash
# Download pre-built assets for RISC-V Linux testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --cpu <name> [--output <path>]

Download pre-built fw_payload.bin and rootfs.ext2 for testing.

Options:
    --cpu <name>      CPU name (e.g., p8700)
    --output <path>   Output directory (default: downloads/<cpu>/)
    --help            Show this help

Example:
    $(basename "$0") --cpu p8700
EOF
}

# Parse arguments
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

if [[ -z "$CPU_ARG" ]]; then
    log_error "Missing required argument: --cpu"
    usage
    exit 1
fi

# Load CPU configuration
load_cpu_config "$CPU_ARG"

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="${PROJECT_ROOT}/downloads/${CPU_NAME}"
fi

ensure_dir "$OUTPUT_DIR"

# Check for required tools
check_command curl

# Download function with retry
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry=0

    log_info "Downloading: $(basename "$output")"
    log_info "  URL: $url"

    while [[ $retry -lt $max_retries ]]; do
        if curl -fSL --progress-bar -o "$output" "$url"; then
            log_success "Downloaded: $(basename "$output")"
            return 0
        fi

        retry=$((retry + 1))
        log_warn "Download failed, retry $retry/$max_retries..."
        sleep 2
    done

    log_error "Failed to download: $url"
    return 1
}

# Verify file exists and has content
verify_file() {
    local file="$1"
    local min_size="${2:-1024}"  # Minimum expected size in bytes

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    local size
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)

    if [[ $size -lt $min_size ]]; then
        log_error "File too small (${size} bytes): $file"
        return 1
    fi

    log_info "Verified: $(basename "$file") (${size} bytes)"
    return 0
}

# Download fw_payload.bin
FW_PAYLOAD_FILE="${OUTPUT_DIR}/fw_payload.bin"
if [[ -f "$FW_PAYLOAD_FILE" ]]; then
    log_info "fw_payload.bin already exists, skipping download"
else
    download_file "$FW_PAYLOAD_URL" "$FW_PAYLOAD_FILE" || exit 1
fi
verify_file "$FW_PAYLOAD_FILE" 1048576 || exit 1  # Expect at least 1MB

# Download rootfs.ext2
ROOTFS_FILE="${OUTPUT_DIR}/rootfs.ext2"
if [[ -f "$ROOTFS_FILE" ]]; then
    log_info "rootfs.ext2 already exists, skipping download"
else
    download_file "$ROOTFS_URL" "$ROOTFS_FILE" || exit 1
fi
verify_file "$ROOTFS_FILE" 1048576 || exit 1  # Expect at least 1MB

log_success "All assets downloaded to: $OUTPUT_DIR"
echo ""
echo "Files:"
ls -lh "$OUTPUT_DIR"
