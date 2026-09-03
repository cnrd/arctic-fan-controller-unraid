#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${BUILD_ROOT:-${repo_root}/build}"
kernel_tree="${UNRAID_KERNEL_TREE:-}"

if [ -z "${kernel_tree}" ] && [ -f "${build_root}/kernel-tree.path" ]; then
  kernel_tree="$(cat "${build_root}/kernel-tree.path")"
fi

[ -n "${kernel_tree}" ] || die "kernel tree path is unknown"
[ -d "${kernel_tree}" ] || die "kernel tree does not exist: ${kernel_tree}"
[ -f "${kernel_tree}/Makefile" ] || die "missing kernel Makefile in ${kernel_tree}"
[ -f "${kernel_tree}/.config" ] || die "missing .config in ${kernel_tree}"

kernelrelease="$(make -s -C "${kernel_tree}" kernelrelease)"
printf '%s\n' "${kernelrelease}" > "${build_root}/kernelrelease"

if grep -q '^CONFIG_MODVERSIONS=y' "${kernel_tree}/.config"; then
  [ -s "${kernel_tree}/Module.symvers" ] || die "CONFIG_MODVERSIONS=y but Module.symvers is missing or empty in ${kernel_tree}"
fi

make -C "${kernel_tree}" modules_prepare

[ -d "${kernel_tree}/include/generated" ] || die "modules_prepare did not create include/generated"

printf 'Prepared kernel tree: %s\n' "${kernel_tree}"
printf 'Kernel release: %s\n' "${kernelrelease}"
