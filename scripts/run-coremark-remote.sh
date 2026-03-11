#!/bin/bash
# Run CoreMark benchmark on RISC-V Linux board via SSH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Parse arguments
USER="$(whoami)"
DEST="${USER}@localhost:/tmp/coremark"
TFTP_DIR="/tftpboot"
KERNEL="$PWD/fw_payload.bin"
UBOOT_PATH="$PWD/u-boot.bin"
TIMEOUT=300
OUTPUT_DIR="$PWD/results/"
COREMARK_BIN="${OUTPUT_DIR}/coremark.exe"
CONFIG_PATH="$PWD/run-coremark-config.toml"
UBOOT_ENV_PATH="$PWD/u-boot-env"
QUIET=false

usage() {
   USAGE="Usage: $(basename "$0") --cpu <name> --rootfs <path> [--kernel <path>]

Run CoreMark benchmark on the FPGA via SSH.

The script setups the necessary boot artefacts, uses SSH in order to connect to
the FPGA and runs the CoreMark benchmark.

Options:
    --dest <remote destination>    SSH destination (default: <username>@localhost:/tmp/coremark)
    --kernel <path>                Path to fw_payload.bin (default: <current_path>/fw_payload.bin)
    --uboot-bin <path>             Path to u-boot.bin (default: <current_path>/u-boot.bin)
    --coremark-bin <path>          Path to CoreMark executable (default: <current_path>/coremark.exe)
    --timeout <seconds>            Execution timeout (default: 300)
    --output <path>                Output directory for results (default: <current_path>/results/)
    --tftp-dir <path>              TFTP server directory (default: /tftpboot)
    --quiet                        Suppress info messages (default: $QUIET)
    --help                         Show this help

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

# Fetch target IP from destination
TARGET_USER_IP="${DEST%:*}"

# Send kernel payload
scp "${KERNEL}" "${TARGET_USER_IP}:${TFTP_DIR}"

# Send U-Boot binary or .mcs
scp "${UBOOT_PATH}" "${DEST}"

ssh "${TARGET_USER_IP}" 'source $HOME/.bash_profile ; python3 -u -' < $PWD/run-coremark-serial.py

exit
