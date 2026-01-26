"""
Lit configuration for tests subdirectory.
"""

import os
import shutil
import lit.formats

# Name of the test suite
config.name = "RISC-V Linux Roundtrip Tests"

# File extensions for test files
config.suffixes = ['.test']

# Test format - use ShTest for shell-based tests with FileCheck
config.test_format = lit.formats.ShTest(execute_external=True)

# Root directory of the test suite
config.test_source_root = os.path.dirname(__file__)
config.test_exec_root = config.test_source_root

# Project root directory (parent of tests/)
project_root = os.path.dirname(os.path.dirname(__file__))

# Define substitutions for use in test files
config.substitutions.append(('%project_root', project_root))
config.substitutions.append(('%scripts', os.path.join(project_root, 'scripts')))
config.substitutions.append(('%downloads', os.path.join(project_root, 'downloads')))
config.substitutions.append(('%configs', os.path.join(project_root, 'configs')))
config.substitutions.append(('%results', os.path.join(project_root, 'results')))

# Find LLVM tools (FileCheck)
def find_llvm_bin_dir():
    """Find LLVM bin directory containing FileCheck."""
    # Common LLVM installation paths
    llvm_paths = [
        '/usr/lib/llvm-19/bin',
        '/usr/lib/llvm-18/bin',
        '/usr/lib/llvm-17/bin',
        '/usr/lib/llvm-16/bin',
        '/usr/lib/llvm-15/bin',
        '/usr/lib/llvm-14/bin',
        '/usr/bin',
        '/usr/local/bin',
    ]
    for path in llvm_paths:
        filecheck = os.path.join(path, 'FileCheck')
        if os.path.isfile(filecheck) and os.access(filecheck, os.X_OK):
            return path
    return None

# Build PATH with additional directories
path_additions = []

# Add LLVM bin directory for FileCheck
llvm_bin = find_llvm_bin_dir()
if llvm_bin:
    path_additions.append(llvm_bin)

# Add TOOLCHAIN_PATH if set
toolchain_path = os.environ.get('TOOLCHAIN_PATH', '')
if toolchain_path and os.path.isdir(toolchain_path):
    path_additions.append(toolchain_path)

# Add directory containing QEMU_BIN if set
qemu_bin = os.environ.get('QEMU_BIN', '')
if qemu_bin and os.path.isfile(qemu_bin):
    path_additions.append(os.path.dirname(qemu_bin))

current_path = os.environ.get('PATH', '')
if path_additions:
    config.environment['PATH'] = ':'.join(path_additions) + ':' + current_path
else:
    config.environment['PATH'] = current_path

# Environment variables
config.environment['PROJECT_ROOT'] = project_root

# Pass through important environment variables
passthrough_vars = [
    'HOME',
    'QEMU_BIN',
    'CROSS_COMPILE',
    'TOOLCHAIN_PATH',
    'LINUX_SRC',
    'OPENSBI_SRC',
]
for var in passthrough_vars:
    if var in os.environ:
        config.environment[var] = os.environ[var]

# Feature detection - use the updated PATH
def which_with_path(cmd):
    """Find command using the configured PATH."""
    for path_dir in config.environment['PATH'].split(':'):
        full_path = os.path.join(path_dir, cmd)
        if os.path.isfile(full_path) and os.access(full_path, os.X_OK):
            return full_path
    return None

# Check for QEMU
qemu_bin_env = os.environ.get('QEMU_BIN', '')
if qemu_bin_env and os.path.isfile(qemu_bin_env) and os.access(qemu_bin_env, os.X_OK):
    config.available_features.add('qemu')
elif which_with_path('qemu-system-riscv64') or shutil.which('qemu-system-riscv64'):
    config.available_features.add('qemu')

# Check for FileCheck
if which_with_path('FileCheck') or shutil.which('FileCheck'):
    config.available_features.add('filecheck')

# Check for debugfs (for rootfs modification)
if shutil.which('debugfs'):
    config.available_features.add('debugfs')

# Check for downloaded assets
p8700_kernel = os.path.join(project_root, 'downloads', 'p8700', 'fw_payload.bin')
p8700_rootfs = os.path.join(project_root, 'downloads', 'p8700', 'rootfs.ext2')
if os.path.exists(p8700_kernel) and os.path.exists(p8700_rootfs):
    config.available_features.add('p8700-assets')

# Check for toolchain
cross_compile = os.environ.get('CROSS_COMPILE', '')
if cross_compile:
    if which_with_path(f'{cross_compile}gcc') or shutil.which(f'{cross_compile}gcc'):
        config.available_features.add('toolchain')

# Timeout for individual tests (in seconds)
config.test_timeout = 300
