#!/bin/bash
# Run CoreMark benchmark on RISC-V Linux via QEMU
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") --cpu <name> --rootfs <path> [--kernel <path>]

Run CoreMark benchmark on RISC-V Linux via QEMU.

The script injects CoreMark into the rootfs with an auto-run init script,
boots QEMU, captures the benchmark output, and exits when complete.

Options:
    --cpu <name>          CPU name (e.g., p8700)
    --rootfs <path>       Path to rootfs.ext2
    --kernel <path>       Path to fw_payload.bin (default: downloads/<cpu>/fw_payload.bin)
    --timeout <seconds>   Execution timeout (default: 300)
    --output <path>       Output directory for results (default: results/)
    --quiet               Suppress info messages, only output QEMU serial
    --help                Show this help

Environment:
    QEMU_BIN              QEMU binary (default: qemu-system-riscv64)

Example:
    $(basename "$0") --cpu p8700 --rootfs downloads/p8700/rootfs.ext2
EOF
}

# Parse arguments
CPU_ARG=""
ROOTFS=""
KERNEL=""
TIMEOUT=300
OUTPUT_DIR=""
QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            CPU_ARG="$2"
            shift 2
            ;;
        --rootfs)
            ROOTFS="$2"
            shift 2
            ;;
        --kernel)
            KERNEL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
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

if [[ -z "$ROOTFS" ]]; then
    log_error "Missing required argument: --rootfs"
    usage
    exit 1
fi

# Set quiet mode for common.sh functions
COMMON_QUIET="$QUIET"

# Load CPU configuration
load_cpu_config "$CPU_ARG"

# Set defaults
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/results}"
KERNEL="${KERNEL:-${PROJECT_ROOT}/downloads/${CPU_NAME}/fw_payload.bin}"

# Validate files exist
if [[ ! -f "$ROOTFS" ]]; then
    die "Rootfs not found: $ROOTFS"
fi

if [[ ! -f "$KERNEL" ]]; then
    die "Kernel not found: $KERNEL"
fi

# Ensure output directory exists
ensure_dir "$OUTPUT_DIR"

# Build CoreMark if not present
COREMARK_BIN="${OUTPUT_DIR}/coremark-${CPU_NAME}.exe"
if [[ ! -f "$COREMARK_BIN" ]]; then
    if [[ "$QUIET" != "true" ]]; then
        log_info "CoreMark binary not found, building..."
        "${SCRIPT_DIR}/build-coremark.sh" --cpu "$CPU_ARG" --output "$OUTPUT_DIR"
    else
        "${SCRIPT_DIR}/build-coremark.sh" --cpu "$CPU_ARG" --output "$OUTPUT_DIR" >/dev/null 2>&1
    fi
fi

if [[ ! -f "$COREMARK_BIN" ]]; then
    die "Failed to build CoreMark"
fi

# Create a modified rootfs with CoreMark and auto-run script
if [[ "$QUIET" != "true" ]]; then
    log_info "Preparing rootfs with CoreMark..."
fi

WORK_DIR=$(mktemp -d)
trap "rm -rf '$WORK_DIR'" EXIT

MODIFIED_ROOTFS="${WORK_DIR}/rootfs.ext2"
cp "$ROOTFS" "$MODIFIED_ROOTFS"
chmod u+w "$MODIFIED_ROOTFS"

# Create the auto-run init script that will execute CoreMark after login
# This script runs as part of the normal init sequence via /etc/init.d/
INIT_SCRIPT="${WORK_DIR}/S99coremark"
cat > "$INIT_SCRIPT" <<'INITSCRIPT'
#!/bin/sh
# CoreMark auto-run init script
case "$1" in
    start)
        echo "=== CoreMark Auto-Run ==="
        echo "Starting CoreMark benchmark..."
        /coremark.exe
        COREMARK_EXIT=$?
        echo "=== CoreMark Complete (exit code: $COREMARK_EXIT) ==="
        echo "COREMARK_TEST_DONE"
        # Power off after benchmark
        sync
        poweroff -f
        ;;
    *)
        ;;
esac
INITSCRIPT
chmod +x "$INIT_SCRIPT"

# Inject files into rootfs
if command -v debugfs &>/dev/null; then
    # Use debugfs (doesn't require root)
    debugfs -w -R "write $COREMARK_BIN /coremark.exe" "$MODIFIED_ROOTFS" 2>/dev/null || {
        die "Failed to inject CoreMark binary using debugfs"
    }
    # Inject init script to /etc/init.d/
    debugfs -w -R "write $INIT_SCRIPT /etc/init.d/S99coremark" "$MODIFIED_ROOTFS" 2>/dev/null || {
        die "Failed to inject init script using debugfs"
    }
    if [[ "$QUIET" != "true" ]]; then
        log_success "Injected files using debugfs"
    fi
elif sudo -n true 2>/dev/null; then
    # Use loop mount with sudo
    MOUNT_POINT="${WORK_DIR}/mnt"
    mkdir -p "$MOUNT_POINT"
    sudo mount -o loop "$MODIFIED_ROOTFS" "$MOUNT_POINT"
    sudo cp "$COREMARK_BIN" "${MOUNT_POINT}/coremark.exe"
    sudo chmod +x "${MOUNT_POINT}/coremark.exe"
    sudo cp "$INIT_SCRIPT" "${MOUNT_POINT}/etc/init.d/S99coremark"
    sudo chmod +x "${MOUNT_POINT}/etc/init.d/S99coremark"
    sudo umount "$MOUNT_POINT"
    if [[ "$QUIET" != "true" ]]; then
        log_success "Injected files using loop mount"
    fi
else
    die "Neither debugfs nor sudo available for rootfs modification"
fi

# Set QEMU binary
QEMU_BIN="${QEMU_BIN:-$DEFAULT_QEMU_BIN}"

# Build QEMU command
QEMU_CMD=(
    "$QEMU_BIN"
    -M "$QEMU_MACHINE"
    -cpu "$QEMU_CPU"
    -m "$QEMU_MEMORY"
    -smp "$QEMU_SMP"
    -kernel "$KERNEL"
    -drive "file=$MODIFIED_ROOTFS,format=raw,snapshot=on"
    -nographic
    -serial mon:stdio
)

if [[ "$QUIET" != "true" ]]; then
    log_info "Running CoreMark via QEMU..."
    log_info "QEMU command: ${QEMU_CMD[*]}"
fi

# Run QEMU and capture output
QEMU_PID=""
TEST_DONE=false
SCORE=""

cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
}
trap "cleanup; rm -rf '$WORK_DIR'" EXIT

# Start QEMU in background
exec 3< <(timeout "$TIMEOUT" "${QEMU_CMD[@]}" 2>&1; echo "___QEMU_EXIT_CODE_$?___")
QEMU_PID=$!

# Read and process output
while IFS= read -r line <&3; do
    # Check for exit marker
    if [[ "$line" =~ ^___QEMU_EXIT_CODE_([0-9]+)___$ ]]; then
        break
    fi

    # Output the line (for lit/FileCheck)
    echo "$line"

    # Extract CoreMark score
    if [[ "$line" =~ Iterations/Sec[[:space:]]*:[[:space:]]*([0-9.]+) ]]; then
        SCORE="${BASH_REMATCH[1]}"
    fi

    # Check for completion marker
    if [[ "$line" == *"COREMARK_TEST_DONE"* ]]; then
        TEST_DONE=true
        sleep 1
        break
    fi
done

exec 3<&-

# Output results summary
if [[ "$TEST_DONE" == "true" ]] && [[ -n "$SCORE" ]]; then
    echo ""
    echo "=== CoreMark Results ==="
    echo "CPU: $CPU_NAME"
    echo "Score: $SCORE iterations/sec"
    echo "Status: PASS"
    exit $EXIT_SUCCESS
elif [[ "$TEST_DONE" == "true" ]]; then
    echo ""
    echo "=== CoreMark Results ==="
    echo "CPU: $CPU_NAME"
    echo "Status: COMPLETED (score not parsed)"
    exit $EXIT_SUCCESS
else
    if [[ "$QUIET" != "true" ]]; then
        log_error "CoreMark test did not complete"
    fi
    exit $EXIT_TEST_FAIL
fi
