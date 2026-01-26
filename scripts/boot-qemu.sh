#!/bin/bash
# Boot Linux via QEMU for RISC-V testing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --cpu <name> --kernel <fw_payload.bin> --rootfs <rootfs.ext2> [options]

Boot Linux kernel via QEMU and monitor for successful boot.

Options:
    --cpu <name>          CPU name (e.g., p8700)
    --kernel <path>       Path to fw_payload.bin or kernel image
    --rootfs <path>       Path to rootfs.ext2
    --smp <N>             Number of CPUs (default: from config)
    --memory <size>       Memory size (default: from config)
    --timeout <seconds>   Boot timeout in seconds (default: 120)
    --stop-pattern <pat>  Pattern to stop QEMU on (default: "login:")
    --interactive         Run QEMU interactively (no timeout)
    --quiet               Suppress info messages, only output QEMU serial
    --help                Show this help

Environment:
    QEMU_BIN              QEMU binary (default: qemu-system-riscv64)

Exit codes:
    0 - Success (stop pattern found)
    1 - Setup failure
    2 - Boot failure (stop pattern not found)
    4 - Timeout

Example:
    $(basename "$0") --cpu p8700 --kernel downloads/p8700/fw_payload.bin --rootfs downloads/p8700/rootfs.ext2
EOF
}

# Parse arguments
CPU_ARG=""
KERNEL=""
ROOTFS=""
SMP=""
MEMORY=""
TIMEOUT=120
STOP_PATTERN="login:"
INTERACTIVE=false
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            CPU_ARG="$2"
            shift 2
            ;;
        --kernel)
            KERNEL="$2"
            shift 2
            ;;
        --rootfs)
            ROOTFS="$2"
            shift 2
            ;;
        --smp)
            SMP="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --stop-pattern)
            STOP_PATTERN="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
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

if [[ -z "$KERNEL" ]]; then
    log_error "Missing required argument: --kernel"
    usage
    exit 1
fi

if [[ -z "$ROOTFS" ]]; then
    log_error "Missing required argument: --rootfs"
    usage
    exit 1
fi

# Set quiet mode for common.sh functions
COMMON_QUIET="$QUIET"

# Load CPU configuration
load_cpu_config "$CPU_ARG"

# Set QEMU binary
QEMU_BIN="${QEMU_BIN:-$DEFAULT_QEMU_BIN}"

# Check QEMU exists
check_command "$QEMU_BIN"

# Validate kernel and rootfs exist
if [[ ! -f "$KERNEL" ]]; then
    die "Kernel not found: $KERNEL"
fi

if [[ ! -f "$ROOTFS" ]]; then
    die "Rootfs not found: $ROOTFS"
fi

# Use config defaults if not specified
SMP="${SMP:-$QEMU_SMP}"
MEMORY="${MEMORY:-$QEMU_MEMORY}"

# Build QEMU command
QEMU_CMD=(
    "$QEMU_BIN"
    -M "$QEMU_MACHINE"
    -cpu "$QEMU_CPU"
    -m "$MEMORY"
    -smp "$SMP"
    -kernel "$KERNEL"
    -drive "file=$ROOTFS,format=raw,snapshot=on"
    -nographic
    -serial mon:stdio
)

if [[ "$QUIET" != "true" ]]; then
    log_info "QEMU command: ${QEMU_CMD[*]}"
    log_info "Boot timeout: ${TIMEOUT}s"
    log_info "Stop pattern: $STOP_PATTERN"
fi

if [[ "$INTERACTIVE" == "true" ]]; then
    log_info "Running QEMU interactively..."
    exec "${QEMU_CMD[@]}"
fi

# Run QEMU with timeout and monitor output for stop pattern
# This approach works well with lit/FileCheck as all output goes to stdout

QEMU_PID=""
PATTERN_FOUND=false

cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Start QEMU in background, redirect output to a pipe
exec 3< <(timeout "$TIMEOUT" "${QEMU_CMD[@]}" 2>&1; echo "___QEMU_EXIT_CODE_$?___")
QEMU_PID=$!

# Read output line by line, checking for stop pattern
START_TIME=$(date +%s)
while IFS= read -r line <&3; do
    # Check for exit marker
    if [[ "$line" =~ ^___QEMU_EXIT_CODE_([0-9]+)___$ ]]; then
        QEMU_EXIT_CODE="${BASH_REMATCH[1]}"
        break
    fi

    # Output the line (for lit/FileCheck to verify)
    echo "$line"

    # Check for stop pattern
    if [[ "$line" == *"$STOP_PATTERN"* ]]; then
        PATTERN_FOUND=true
        if [[ "$QUIET" != "true" ]]; then
            echo "[boot-qemu] Stop pattern found: $STOP_PATTERN" >&2
        fi
        # Give a moment for any trailing output, then exit
        sleep 1
        break
    fi

    # Check for timeout
    CURRENT_TIME=$(date +%s)
    if (( CURRENT_TIME - START_TIME > TIMEOUT )); then
        if [[ "$QUIET" != "true" ]]; then
            echo "[boot-qemu] Timeout reached" >&2
        fi
        break
    fi
done

exec 3<&-

# Determine exit code
if [[ "$PATTERN_FOUND" == "true" ]]; then
    exit $EXIT_SUCCESS
elif [[ "${QEMU_EXIT_CODE:-0}" -eq 124 ]]; then
    if [[ "$QUIET" != "true" ]]; then
        log_error "Boot timed out after ${TIMEOUT}s"
    fi
    exit $EXIT_TIMEOUT
else
    if [[ "$QUIET" != "true" ]]; then
        log_error "Boot failed - stop pattern not found"
    fi
    exit $EXIT_BOOT_FAIL
fi
