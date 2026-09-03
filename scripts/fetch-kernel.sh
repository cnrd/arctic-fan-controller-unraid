#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${BUILD_ROOT:-${repo_root}/build}"
kernel_tree="${UNRAID_KERNEL_TREE:-${build_root}/kernel-tree}"
mode="${UNRAID_KERNEL_SOURCE_MODE:-local}"

mkdir -p "${build_root}"

case "${mode}" in
  local)
    [ -n "${UNRAID_KERNEL_TREE:-}" ] || die "UNRAID_KERNEL_TREE is required when UNRAID_KERNEL_SOURCE_MODE=local"
    [ -d "${UNRAID_KERNEL_TREE}" ] || die "UNRAID_KERNEL_TREE does not exist: ${UNRAID_KERNEL_TREE}"
    log "Using local Unraid kernel tree: ${UNRAID_KERNEL_TREE}"
    ;;
  ich777)
    image="${ICH777_UNRAID_KERNEL_IMAGE:-}"
    [ -n "${image}" ] || die "ICH777_UNRAID_KERNEL_IMAGE is required when UNRAID_KERNEL_SOURCE_MODE=ich777"
    command -v docker >/dev/null 2>&1 || die "docker is required for UNRAID_KERNEL_SOURCE_MODE=ich777"
    container="arctic-kernel-${GITHUB_RUN_ID:-manual}-$$"
    rm -rf "${kernel_tree}"
    log "Pulling ${image}"
    docker pull "${image}"
    log "Creating temporary container ${container}"
    docker create --name "${container}" "${image}" >/dev/null
    trap 'docker rm -f "${container}" >/dev/null 2>&1 || true' EXIT
    log "Copying /usr/src from container"
    mkdir -p "${build_root}/ich777-root"
    docker cp "${container}:/usr/src" "${build_root}/ich777-root"
    found="$(find "${build_root}/ich777-root/usr/src" -maxdepth 2 -type f -name Module.symvers -print -quit || true)"
    [ -n "${found}" ] || die "could not find Module.symvers in copied ich777 image; inspect image layout"
    kernel_tree="$(dirname "${found}")"
    log "Discovered kernel tree: ${kernel_tree}"
    printf '%s\n' "${kernel_tree}" > "${build_root}/kernel-tree.path"
    ;;
  official-zip)
    die "official-zip mode is reserved until target-release extraction is pinned; do not guess Unraid build inputs"
    ;;
  *)
    die "unsupported UNRAID_KERNEL_SOURCE_MODE: ${mode}"
    ;;
esac

if [ "${mode}" = "local" ]; then
  printf '%s\n' "${UNRAID_KERNEL_TREE}" > "${build_root}/kernel-tree.path"
fi
