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

mkdir -p "${dist_dir}"
modinfo "${module}" | tee "${dist_dir}/modinfo.txt"
file "${module}" | tee "${dist_dir}/file.txt"

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

if ! modinfo -F alias "${module}" | grep -qi 'v00003904p0000F001'; then
  die "expected HID alias for VID 3904 PID F001 not found"
fi

printf 'Compile-time verification passed for %s\n' "${module}"
