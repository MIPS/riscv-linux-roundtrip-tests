#!/bin/bash
# Check that the environment is properly configured for RISC-V Linux testing
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

check_var() {
    local var_name="$1"
    local required="$2"
    local description="$3"

    if [[ -z "${!var_name:-}" ]]; then
        if [[ "$required" == "required" ]]; then
            echo -e "${RED}[ERROR]${NC} $var_name is not set"
            echo "        $description"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${YELLOW}[WARN]${NC}  $var_name is not set (optional)"
            echo "        $description"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    else
        echo -e "${GREEN}[OK]${NC}    $var_name=${!var_name}"
        return 0
    fi
}

check_command() {
    local cmd="$1"
    local description="$2"

    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC}    $cmd found: $(command -v "$cmd")"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} $cmd not found in PATH"
        echo "        $description"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

check_path() {
    local var_name="$1"
    local path_type="$2"  # "file" or "dir"
    local required="$3"
    local description="$4"

    if [[ -z "${!var_name:-}" ]]; then
        if [[ "$required" == "required" ]]; then
            echo -e "${RED}[ERROR]${NC} $var_name is not set"
            echo "        $description"
            ERRORS=$((ERRORS + 1))
        fi
        return 1
    fi

    local path="${!var_name}"
    if [[ "$path_type" == "file" && -f "$path" ]]; then
        echo -e "${GREEN}[OK]${NC}    $var_name exists: $path"
        return 0
    elif [[ "$path_type" == "dir" && -d "$path" ]]; then
        echo -e "${GREEN}[OK]${NC}    $var_name exists: $path"
        return 0
    else
        if [[ "$required" == "required" ]]; then
            echo -e "${RED}[ERROR]${NC} $var_name path does not exist: $path"
            ERRORS=$((ERRORS + 1))
        else
            echo -e "${YELLOW}[WARN]${NC}  $var_name path does not exist: $path"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    fi
}

echo "========================================"
echo "RISC-V Linux Roundtrip Tests - Environment Check"
echo "========================================"
echo ""

echo "=== Required Environment Variables ==="
echo ""

check_var "QEMU_BIN" "required" \
    "Path to qemu-system-riscv64 binary"

check_var "CROSS_COMPILE" "required" \
    "Cross compiler prefix (e.g., riscv64-linux-gnu-)"

echo ""
echo "=== Optional Environment Variables ==="
echo ""

check_var "TOOLCHAIN_PATH" "optional" \
    "Path to toolchain bin directory (added to PATH)"

check_var "LINUX_SRC" "optional" \
    "Path to Linux kernel source tree (for build-linux.sh)"

check_var "OPENSBI_SRC" "optional" \
    "Path to OpenSBI source tree (for build-opensbi.sh)"

echo ""
echo "=== Path Validation ==="
echo ""

if [[ -n "${QEMU_BIN:-}" ]]; then
    check_path "QEMU_BIN" "file" "required" "QEMU binary must exist"
fi

if [[ -n "${TOOLCHAIN_PATH:-}" ]]; then
    check_path "TOOLCHAIN_PATH" "dir" "optional" "Toolchain directory"
fi

if [[ -n "${LINUX_SRC:-}" ]]; then
    check_path "LINUX_SRC" "dir" "optional" "Linux source directory"
fi

if [[ -n "${OPENSBI_SRC:-}" ]]; then
    check_path "OPENSBI_SRC" "dir" "optional" "OpenSBI source directory"
fi

echo ""
echo "=== Tool Availability ==="
echo ""

# Check cross compiler
if [[ -n "${CROSS_COMPILE:-}" ]]; then
    # Add toolchain to PATH if set
    if [[ -n "${TOOLCHAIN_PATH:-}" && -d "${TOOLCHAIN_PATH}" ]]; then
        export PATH="${TOOLCHAIN_PATH}:$PATH"
    fi
    check_command "${CROSS_COMPILE}gcc" "Cross compiler gcc"
fi

# Check for FileCheck (for lit tests)
check_command "FileCheck" "LLVM FileCheck (install llvm package)" || true

# Check for lit (for running tests)
check_command "lit" "LLVM lit test runner (pip install lit)" || true

# Check for debugfs (for rootfs modification)
check_command "debugfs" "debugfs for ext2 filesystem modification (install e2fsprogs)" || true

# Check for curl (for downloading assets)
check_command "curl" "curl for downloading files" || true

echo ""
echo "========================================"

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}Environment check FAILED with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please set the required environment variables. Example:"
    echo ""
    echo "  export QEMU_BIN=/path/to/qemu-system-riscv64"
    echo "  export CROSS_COMPILE=riscv64-linux-gnu-"
    echo "  export TOOLCHAIN_PATH=/path/to/toolchain/bin  # optional"
    echo "  export LINUX_SRC=/path/to/linux              # optional"
    echo "  export OPENSBI_SRC=/path/to/opensbi          # optional"
    echo ""
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}Environment check PASSED with $WARNINGS warning(s)${NC}"
    echo ""
    exit 0
else
    echo -e "${GREEN}Environment check PASSED${NC}"
    echo ""
    exit 0
fi
