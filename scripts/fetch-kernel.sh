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
kernel_source_json="${build_root}/kernel-source.json"

case "${mode}" in
  local)
    [ -n "${UNRAID_KERNEL_TREE:-}" ] || die "UNRAID_KERNEL_TREE is required when UNRAID_KERNEL_SOURCE_MODE=local"
    [ -d "${UNRAID_KERNEL_TREE}" ] || die "UNRAID_KERNEL_TREE does not exist: ${UNRAID_KERNEL_TREE}"
    log "Using local Unraid kernel tree: ${UNRAID_KERNEL_TREE}"
    cat > "${kernel_source_json}" <<EOF
{
  "mode": "local",
  "kernel_tree": "${UNRAID_KERNEL_TREE}",
  "sha256_expected": null,
  "sha256_actual": null,
  "sha256_verified": null
}
EOF
    ;;
  ich777)
    release="${EXPECTED_KERNELRELEASE:-}"
    archive_url="${ICH777_UNRAID_KERNEL_ARCHIVE_URL:-}"
    archive_sha256="${ICH777_UNRAID_KERNEL_ARCHIVE_SHA256:-}"
    image="${ICH777_UNRAID_KERNEL_IMAGE:-}"
    require_sha256="${REQUIRE_KERNEL_ARCHIVE_SHA256:-false}"

    if [ -z "${archive_url}" ] && [ -n "${release}" ]; then
      archive_url="https://github.com/ich777/unraid_kernel/releases/download/${release}/linux-${release}.tar.xz"
    fi

    rm -rf "${kernel_tree}"

    if [ -n "${archive_url}" ]; then
      command -v curl >/dev/null 2>&1 || die "curl is required to download ${archive_url}"
      command -v tar >/dev/null 2>&1 || die "tar is required to extract ${archive_url}"
      command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required to record ${archive_url}"
      archive="${build_root}/$(basename "${archive_url%%\?*}")"
      log "Downloading ${archive_url}"
      curl -L --fail --retry 3 --retry-delay 2 -o "${archive}.tmp" "${archive_url}"
      mv "${archive}.tmp" "${archive}"
      actual_sha256="$(sha256sum "${archive}" | awk '{print $1}')"
      sha256_verified="false"
      if [ -n "${archive_sha256}" ]; then
        [ "${actual_sha256}" = "${archive_sha256}" ] || die "SHA256 mismatch for ${archive}: expected ${archive_sha256}, got ${actual_sha256}"
        sha256_verified="true"
      elif [ "${require_sha256}" = "true" ]; then
        die "kernel archive SHA256 is required but was not provided for ${archive_url}"
      fi
      sha256_expected_json="null"
      if [ -n "${archive_sha256}" ]; then
        sha256_expected_json="\"${archive_sha256}\""
      fi
      mkdir -p "${kernel_tree}"
      log "Extracting ${archive}"
      tar -xf "${archive}" -C "${kernel_tree}"
      cat > "${kernel_source_json}" <<EOF
{
  "mode": "ich777",
  "source": "archive",
  "expected_kernelrelease": "${release}",
  "archive_url": "${archive_url}",
  "archive_file": "${archive}",
  "sha256_expected": ${sha256_expected_json},
  "sha256_actual": "${actual_sha256}",
  "sha256_verified": ${sha256_verified}
}
EOF
    elif [ -n "${image}" ]; then
      command -v docker >/dev/null 2>&1 || die "docker is required for ICH777_UNRAID_KERNEL_IMAGE"
      container="arctic-kernel-${GITHUB_RUN_ID:-manual}-$$"
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
      cat > "${kernel_source_json}" <<EOF
{
  "mode": "ich777",
  "source": "image",
  "expected_kernelrelease": "${release}",
  "image": "${image}",
  "sha256_expected": null,
  "sha256_actual": null,
  "sha256_verified": null
}
EOF
    else
      die "EXPECTED_KERNELRELEASE or ICH777_UNRAID_KERNEL_ARCHIVE_URL is required for ich777 tarball mode; alternatively set ICH777_UNRAID_KERNEL_IMAGE"
    fi

    log "Discovered kernel tree: ${kernel_tree}"
    printf '%s\n' "${kernel_tree}" > "${build_root}/kernel-tree.path"
    ;;
  official-zip)
    die "official-zip mode is blocked: inspected Unraid 7.3.2 installer/runtime images verify uname -r but do not include /usr/src, .config, or Module.symvers"
    ;;
  *)
    die "unsupported UNRAID_KERNEL_SOURCE_MODE: ${mode}"
    ;;
esac

if [ "${mode}" = "local" ]; then
  printf '%s\n' "${UNRAID_KERNEL_TREE}" > "${build_root}/kernel-tree.path"
fi
