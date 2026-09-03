#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${BUILD_ROOT:-${repo_root}/build}"
dist_dir="${DIST_DIR:-${repo_root}/dist}"
module="${1:-${dist_dir}/arctic_fan_controller.ko}"
expected_release="${EXPECTED_KERNELRELEASE:-}"

if [ -z "${expected_release}" ] && [ -f "${build_root}/kernelrelease" ]; then
  expected_release="$(cat "${build_root}/kernelrelease")"
fi

[ -f "${module}" ] || die "module does not exist: ${module}"
command -v modinfo >/dev/null 2>&1 || die "modinfo is required"
command -v file >/dev/null 2>&1 || die "file is required"
command -v readelf >/dev/null 2>&1 || die "readelf is required"
command -v nm >/dev/null 2>&1 || die "nm is required"

mkdir -p "${dist_dir}"
modinfo "${module}" | tee "${dist_dir}/modinfo.txt"
file "${module}" | tee "${dist_dir}/file.txt"
readelf -h "${module}" | tee "${dist_dir}/readelf-header.txt"
nm -u "${module}" | tee "${dist_dir}/undefined-symbols.txt"

if readelf -S "${module}" | grep -q ' __versions '; then
  readelf -x __versions "${module}" | tee "${dist_dir}/modversions.txt"
else
  printf 'No __versions section found; CONFIG_MODVERSIONS may be disabled for this target.\n' | tee "${dist_dir}/modversions.txt"
fi

{
  printf 'runner_uname_r=%s\n' "$(uname -r)"
  printf 'module_vermagic=%s\n' "$(modinfo -F vermagic "${module}")"
  printf 'expected_kernelrelease=%s\n' "${expected_release}"
} | tee "${dist_dir}/kernel-context.txt"

name="$(modinfo -F name "${module}")"
[ "${name}" = "arctic_fan_controller" ] || die "unexpected module name: ${name}"

if [ -n "${expected_release}" ]; then
  vermagic="$(modinfo -F vermagic "${module}")"
  case "${vermagic}" in
    "${expected_release}"*) ;;
    *) die "vermagic '${vermagic}' does not start with expected kernel release '${expected_release}'" ;;
  esac
fi

if ! grep -q 'x86-64\|x86_64\|ELF 64-bit.*x86-64' "${dist_dir}/file.txt"; then
  die "module file output does not identify x86-64"
fi

if ! grep -q 'Machine:.*X86-64' "${dist_dir}/readelf-header.txt"; then
  die "readelf header does not identify x86-64"
fi

if ! modinfo -F alias "${module}" | grep -qi 'v00003904p0000F001'; then
  die "expected HID alias for VID 3904 PID F001 not found"
fi

printf 'Compile-time verification passed for %s\n' "${module}"
