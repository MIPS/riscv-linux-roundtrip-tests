# RISC-V Linux Roundtrip Tests

Automated testing framework for Linux kernel patches on MIPS RISC-V CPUs.

## Overview

This framework provides scripts to build, boot, and test Linux kernels on MIPS RISC-V processors (starting with P8700). It supports testing via QEMU emulation and includes benchmarks like CoreMark.

Tests are organized using [LLVM lit](https://llvm.org/docs/CommandGuide/lit.html) with `FileCheck` for pattern matching, providing a portable and CI-friendly test infrastructure.

## Supported CPUs

| CPU | Architecture | QEMU Machine | Status |
|-----|--------------|--------------|--------|
| P8700 | RISC-V 64-bit | boston-aia | Supported |

## Test Status

### P8700

- [x] QEMU boot
- [ ] FPGA boot
- [x] CoreMark (QEMU)
- [ ] CoreMark (FPGA)
- [ ] kselftest (QEMU)
- [ ] kselftest (FPGA)
- [ ] LTP (QEMU)
- [ ] LTP (FPGA)

## Prerequisites

- QEMU with RISC-V support (qemu-system-riscv64)
- RISC-V cross-compiler toolchain
- curl (for downloading assets)
- LLVM lit and FileCheck (for running tests)
- debugfs (for rootfs modification, part of e2fsprogs)

### Installing lit and FileCheck

```bash
# Using pip
pip install lit

# FileCheck is part of LLVM
# Ubuntu/Debian:
apt install llvm

# Or build from LLVM source
```

## Environment Setup

Before using this framework, set the required environment variables:

```bash
# Required
export QEMU_BIN=/path/to/qemu-system-riscv64
export CROSS_COMPILE=riscv64-mti-linux-gnu-

# Optional (for building)
export TOOLCHAIN_PATH=/path/to/toolchain/bin
export LINUX_SRC=/path/to/linux
export OPENSBI_SRC=/path/to/opensbi
```

Run the environment check script to verify your setup:

```bash
./scripts/check-env.sh
```

## Quick Start

### 1. Check Environment

```bash
./scripts/check-env.sh
```

This verifies that required environment variables (`QEMU_BIN`, `CROSS_COMPILE`) are set correctly.

### 2. Download Pre-built Assets

```bash
./scripts/download-assets.sh --cpu p8700
```

This downloads `fw_payload.bin` and `rootfs.ext2` to `downloads/p8700/`.

### 3. Run All Tests with lit

```bash
# Run all tests
lit tests/

# Run with verbose output
lit -v tests/

# Run specific test
lit tests/p8700/boot.test

# Run tests for a specific CPU
lit tests/p8700/
```

### 4. Run Individual Scripts

```bash
# Boot test (standalone)
./scripts/boot-qemu.sh --cpu p8700 \
    --kernel downloads/p8700/fw_payload.bin \
    --rootfs downloads/p8700/rootfs.ext2

# CoreMark benchmark
./scripts/run-coremark.sh --cpu p8700 --rootfs downloads/p8700/rootfs.ext2
```

### 5. Build Linux Kernel (Optional)

```bash
./scripts/build-linux.sh --cpu p8700
```

### 6. Build OpenSBI with Custom Kernel (Optional)

```bash
./scripts/build-opensbi.sh --cpu p8700 --payload results/Image-p8700
```

## Directory Structure

```
riscv-linux-roundtrip-tests/
├── README.md                      # This file
├── .gitignore
├── lit.cfg.py                     # LLVM lit configuration
├── configs/
│   └── p8700.conf                 # P8700 CPU configuration
├── scripts/
│   ├── lib/
│   │   └── common.sh              # Shared functions
│   ├── check-env.sh               # Environment check script
│   ├── build-linux.sh             # Build Linux kernel
│   ├── build-opensbi.sh           # Build OpenSBI fw_payload.bin
│   ├── build-coremark.sh          # Build CoreMark benchmark
│   ├── boot-qemu.sh               # Boot via QEMU
│   ├── run-coremark.sh            # Run CoreMark benchmark
│   └── download-assets.sh         # Download pre-built artifacts
├── tests/
│   ├── lit.cfg.py                 # Test suite lit configuration
│   └── p8700/
│       ├── boot.test              # Boot test with FileCheck
│       ├── boot-patterns.test     # Detailed boot pattern test
│       └── coremark.test          # CoreMark benchmark test
├── downloads/                     # Downloaded assets (gitignored)
└── results/                       # Test results (gitignored)
```

## Test Framework

### lit Test Files

Tests use LLVM lit format with FileCheck for output verification:

```
# Example test file: tests/p8700/boot.test

# REQUIRES: qemu
# REQUIRES: p8700-assets

# RUN: %scripts/boot-qemu.sh --cpu p8700 \
# RUN:     --kernel %downloads/p8700/fw_payload.bin \
# RUN:     --rootfs %downloads/p8700/rootfs.ext2 \
# RUN:     --timeout 120 --quiet 2>&1 | FileCheck %s

# CHECK: OpenSBI
# CHECK: Linux version
# CHECK: login:
```

### Available Features

Tests can require specific features using `REQUIRES:` directives:

| Feature | Description |
|---------|-------------|
| `qemu` | QEMU binary is available |
| `filecheck` | FileCheck tool is available |
| `debugfs` | debugfs tool for rootfs modification |
| `toolchain` | Cross-compiler toolchain is available |
| `p8700-assets` | P8700 fw_payload.bin and rootfs.ext2 downloaded |

### Substitutions

Test files can use these substitutions:

| Substitution | Expands To |
|--------------|------------|
| `%project_root` | Project root directory |
| `%scripts` | scripts/ directory |
| `%downloads` | downloads/ directory |
| `%configs` | configs/ directory |
| `%results` | results/ directory |

## Scripts Reference

### download-assets.sh

Download pre-built fw_payload.bin and rootfs.ext2.

```bash
./scripts/download-assets.sh --cpu <name> [--output <path>]
```

### boot-qemu.sh

Boot Linux via QEMU emulation.

```bash
./scripts/boot-qemu.sh --cpu <name> --kernel <fw_payload.bin> --rootfs <rootfs.ext2> [options]

Options:
    --smp <N>             Number of CPUs (default: from config)
    --memory <size>       Memory size (default: from config)
    --timeout <seconds>   Boot timeout (default: 120)
    --stop-pattern <pat>  Pattern to stop on (default: "login:")
    --interactive         Run QEMU interactively
    --quiet               Suppress info messages (for lit)
```

### build-linux.sh

Build Linux kernel Image.

```bash
./scripts/build-linux.sh --cpu <name> [--linux-src <path>] [--output <path>]

Options:
    --defconfig <name>    Defconfig to use (default: from config)
    --jobs <N>            Parallel jobs (default: nproc)
```

### build-opensbi.sh

Build OpenSBI fw_payload.bin with embedded Linux kernel.

```bash
./scripts/build-opensbi.sh --cpu <name> --payload <Image> [--output <path>]

Options:
    --opensbi-src <path>  OpenSBI source path
    --jobs <N>            Parallel jobs (default: nproc)
```

### build-coremark.sh

Build CoreMark benchmark as a static binary.

```bash
./scripts/build-coremark.sh --cpu <name> [--output <path>]
```

### run-coremark.sh

Run CoreMark benchmark via QEMU.

```bash
./scripts/run-coremark.sh --cpu <name> --rootfs <path> [--kernel <path>]

Options:
    --timeout <seconds>   Execution timeout (default: 300)
    --quiet               Suppress info messages (for lit)
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `QEMU_BIN` | Yes | Path to qemu-system-riscv64 binary |
| `CROSS_COMPILE` | Yes | Cross compiler prefix (e.g., `riscv64-linux-gnu-`) |
| `TOOLCHAIN_PATH` | No | Toolchain bin directory (added to PATH) |
| `LINUX_SRC` | For builds | Path to Linux kernel source tree |
| `OPENSBI_SRC` | For builds | Path to OpenSBI source tree |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Build/setup failure |
| 2 | Boot failure |
| 3 | Test failure |
| 4 | Timeout |

## Adding a New CPU

1. Create a configuration file in `configs/<cpu_name>.conf`
2. Define required variables:
   - `CPU_NAME`, `ARCH`, `CROSS_COMPILE`
   - `QEMU_MACHINE`, `QEMU_CPU`, `QEMU_MEMORY`, `QEMU_SMP`
   - `DEFCONFIG`, `BOOT_PATTERNS`
   - `FW_PAYLOAD_URL`, `ROOTFS_URL`
3. Create test files in `tests/<cpu_name>/`
4. Add feature detection in `lit.cfg.py` if needed

## CI Integration

The lit-based test framework integrates easily with CI systems:

```yaml
# Example GitHub Actions
- name: Set up environment
  run: |
    echo "QEMU_BIN=$(which qemu-system-riscv64)" >> $GITHUB_ENV
    echo "CROSS_COMPILE=riscv64-linux-gnu-" >> $GITHUB_ENV

- name: Check environment
  run: ./scripts/check-env.sh

- name: Download assets
  run: ./scripts/download-assets.sh --cpu p8700

- name: Run tests
  run: lit -v tests/
```

## License

See individual component licenses:
- Linux kernel: GPL-2.0
- OpenSBI: BSD-2-Clause
- CoreMark: Apache-2.0
