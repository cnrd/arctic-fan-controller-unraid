#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${BUILD_ROOT:-${repo_root}/build}"
dist_dir="${DIST_DIR:-${repo_root}/dist}"
kernel_tree="${UNRAID_KERNEL_TREE:-}"
module_source_dir="${build_root}/module-source"
patch_dir="${repo_root}/patches"
patch_manifest="${build_root}/applied-patches.json"

if [ -z "${kernel_tree}" ] && [ -f "${build_root}/kernel-tree.path" ]; then
  kernel_tree="$(cat "${build_root}/kernel-tree.path")"
fi

[ -n "${kernel_tree}" ] || die "kernel tree path is unknown"
[ -d "${kernel_tree}" ] || die "kernel tree does not exist: ${kernel_tree}"
[ -f "${kernel_tree}/.config" ] || die "missing .config in ${kernel_tree}"

mkdir -p "${dist_dir}" "${build_root}/logs"
command -v patch >/dev/null 2>&1 || die "patch is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"

rm -rf -- "${module_source_dir}"
mkdir -p "${module_source_dir}"
cp "${repo_root}/driver/Makefile" "${repo_root}/driver/compat.h" \
  "${repo_root}/driver/arctic_fan_controller.c" "${module_source_dir}/"
applied_patches='[]'
for patch_file in "${patch_dir}"/*.patch; do
  [ -e "${patch_file}" ] || continue
  patch --directory="${module_source_dir}" --strip=1 --batch --forward < "${patch_file}"
  patch_path="patches/${patch_file##*/}"
  patch_sha256="$(sha256sum "${patch_file}" | cut -d' ' -f1)"
  applied_patches="$(jq -c \
    --arg file "${patch_path}" \
    --arg sha256 "${patch_sha256}" \
    '. + [{file: $file, sha256: $sha256}]' <<< "${applied_patches}")"
done
printf '%s\n' "${applied_patches}" | jq . > "${patch_manifest}"

make -C "${kernel_tree}" M="${module_source_dir}" modules 2>&1 | tee "${build_root}/logs/build-module.log"

[ -f "${module_source_dir}/arctic_fan_controller.ko" ] || die "module was not produced"
cp "${module_source_dir}/arctic_fan_controller.ko" "${dist_dir}/"

printf 'Built %s\n' "${dist_dir}/arctic_fan_controller.ko"
