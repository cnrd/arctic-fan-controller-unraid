#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${BUILD_ROOT:-${repo_root}/build}"
dist_dir="${DIST_DIR:-${repo_root}/dist}"
kernel_tree="${UNRAID_KERNEL_TREE:-}"

if [ -z "${kernel_tree}" ] && [ -f "${build_root}/kernel-tree.path" ]; then
  kernel_tree="$(cat "${build_root}/kernel-tree.path")"
fi

[ -n "${kernel_tree}" ] || die "kernel tree path is unknown"
[ -d "${kernel_tree}" ] || die "kernel tree does not exist: ${kernel_tree}"
[ -f "${kernel_tree}/.config" ] || die "missing .config in ${kernel_tree}"

mkdir -p "${dist_dir}" "${build_root}/logs"

make -C "${kernel_tree}" M="${repo_root}/driver" modules 2>&1 | tee "${build_root}/logs/build-module.log"

[ -f "${repo_root}/driver/arctic_fan_controller.ko" ] || die "module was not produced"
cp "${repo_root}/driver/arctic_fan_controller.ko" "${dist_dir}/"

printf 'Built %s\n' "${dist_dir}/arctic_fan_controller.ko"
