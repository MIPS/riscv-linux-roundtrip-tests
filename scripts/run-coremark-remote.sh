#!/bin/bash
# Run CoreMark benchmark on RISC-V Linux board via SSH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Parse arguments
USER="$(whoami)"
DEST="${USER}@localhost"
TFTP_DIR="/srv/tftp/"
KERNEL="$PWD/fw_payload.bin"
UBOOT_PATH="$PWD/u-boot.bin"
TIMEOUT=300
OUTPUT_DIR="$PWD/results/"
COREMARK_BIN="$PWD/coremark.exe"
CONFIG_PATH="$PWD/run-coremark-config.toml"
UBOOT_ENV_PATH="$PWD/u-boot-env"
QUIET=false

usage() {
   USAGE="Usage: $(basename "$0") --cpu <name> --rootfs <path> [--kernel <path>]

Run CoreMark benchmark on the FPGA via SSH.

The script setups the necessary boot artefacts, uses SSH in order to connect to
the FPGA and runs the CoreMark benchmark.

Options:
    --dest <remote destination>    SSH destination (default: localhost)
    --kernel <path>                Path to fw_payload.bin (default: <current_path>/fw_payload.bin)
    --uboot-bin <path>             Path to u-boot.bin (default: <current_path>/u-boot.bin)
    --coremark-bin <path>          Path to CoreMark executable (default: <current_path>/coremark.exe)
    --patch-env <path>             Patch U-Boot environment (default: <current_path>/u-boot-env)
    --timeout <seconds>            Execution timeout (default: 300)
    --output <path>                Output directory for results (default: <current_path>/results/)
    --tftp-dir <path>              TFTP server directory (default: /srv/tftp/)
    --quiet                        Suppress info messages (default: $QUIET)
    --help                         Show this help

Environment:
    QEMU_BIN                       QEMU binary (default: qemu-system-riscv64)

Example:
    $(basename "$0") --dest user@10.10.10.10 --kernel /home/user/fw_payload.bin
"
   echo "$USAGE"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)
            DEST="$2"
            shift 2
            ;;
        --kernel)
            KERNEL="$2"
            shift 2
            ;;
        --uboot-bin)
            UBOOT_PATH="$2"
            shift 2
            ;;
        --coremark-bin)
            COREMARK_BIN="$2"
            shift 2
            ;;
        --tftp-dir)
            TFTP_DIR="$2"
            shift 2
            ;;
        --patch-env)
            UBOOT_ENV_PATH="$2"
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

# Ensure output directory exists
ensure_dir "$OUTPUT_DIR"

# Make TFTP directory if it doesn't exist
if [[ ! -d "$TFTP_DIR" ]]; then
    sudo mkdir -p "$$TFTP_DIR"
fi

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

cp $KERNEL $TFTP_DIR

IP_ADDR="${$(hostname -I)%% *}"
HOST="${USER}@${IP_ADDR}"

# Put enviroment variables into FPGA_ENV
FPGA_ENV=${$(cat ${UBOOT_ENV_PATH})//IP_ADDR/$IP_ADDR}

MKENVIMAGE="$HOME/source/MIPS/riscv-u-boot/tools/mkenvimage"
UBOOT_ENV_BIN="$TFTP_DIR/uboot-env.bin"
UBOOT_ENV_MCS="$TFTP_DIR/uboot-env.mcs"
${MKENVIMAGE} -s 0x40000 -p 0x00 -o ${UBOOT_ENV_BIN} - <<< ${FPGA_ENV}
srec_cat -output ${UBOOT_ENV_MCS} -intel \
    ${UBOOT_ENV_BIN} -binary \
    -fill 0x00 -within ${UBOOT_ENV_BIN} -binary -range-pad 16 \
    -offset 0x7c00000

scp "${UBOOT}" "${DEST}:/tmp/coremark/"
scp "${CONFIG_PATH}" "${DEST}:/tmp/coremark/"
scp "${OUTPUT_DIR}/coremark.exe" "${DEST}:/tmp/coremark/"

ssh "${DEST}" 'python3 -u -' < $PWD/run-coremark-serial.py

exit
