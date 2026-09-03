#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
loader="${repo_root}/plugin/usr/local/sbin/arctic-fan-controller-loader"
tmp_root=""
failures=0

setup() {
  tmp_root="$(mktemp -d /tmp/arctic-loader-tests.XXXXXX)"
  mkdir -p "${tmp_root}/bin" "${tmp_root}/cache" "${tmp_root}/tmp" "${tmp_root}/releases"
  unset AFC_TEST_LOADED AFC_TEST_NATIVE_PATH AFC_TEST_MODULE_NAME AFC_TEST_MODULE_VERMAGIC AFC_TEST_MODULE_ALIAS

  cat > "${tmp_root}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    --*) shift ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
[ -n "${out}" ] && [ -n "${url}" ] || exit 2
[ -f "${url}" ] || exit 22
cp "${url}" "${out}"
EOF

  cat > "${tmp_root}/bin/modinfo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-k" ] && [ "${3:-}" = "-n" ]; then
  if [ -n "${AFC_TEST_NATIVE_PATH:-}" ]; then
    [ "${AFC_TEST_NATIVE_PATH}" = "none" ] && exit 1
    printf '%s\n' "${AFC_TEST_NATIVE_PATH}"
    exit 0
  fi
  exit 1
fi
if [ "${1:-}" = "-F" ]; then
  field="$2"
  module="$3"
  case "${field}" in
    name) printf '%s\n' "${AFC_TEST_MODULE_NAME:-arctic_fan_controller}" ;;
    vermagic) printf '%s SMP preempt mod_unload \n' "${AFC_TEST_MODULE_VERMAGIC:-${AFC_KERNELRELEASE}}" ;;
    alias) printf '%s\n' "${AFC_TEST_MODULE_ALIAS:-hid:b0003g*v00003904p0000F001}" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 1
EOF

  cat > "${tmp_root}/bin/lsmod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'Module Size Used by\n'
if [ "${AFC_TEST_LOADED:-0}" = "1" ]; then
  printf 'arctic_fan_controller 12345 0\n'
fi
EOF

  cat > "${tmp_root}/bin/insmod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >> "${AFC_TEST_INSMOD_LOG}"
EOF

  cat > "${tmp_root}/bin/modprobe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >> "${AFC_TEST_MODPROBE_LOG}"
EOF

  chmod 755 "${tmp_root}/bin/"*
  : > "${tmp_root}/insmod.log"
  : > "${tmp_root}/modprobe.log"
}

teardown() {
  [ -z "${tmp_root}" ] || rm -rf "${tmp_root}"
}

manifest() {
  local kernel="$1"
  local sha="$2"
  local name="${3:-arctic_fan_controller}"
  local verified="${4:-true}"
  cat <<EOF
{
  "schema_version": 1,
  "target": {"kernelrelease": "${kernel}"},
  "kernel_source": {"sha256_verified": ${verified}},
  "module": {"file": "arctic_fan_controller.ko", "name": "${name}", "sha256": "${sha}"}
}
EOF
}

make_module_set() {
  local dir="$1"
  local kernel="$2"
  local body="${3:-module-${kernel}}"
  local manifest_kernel="${4:-${kernel}}"
  local manifest_sha_override="${5:-}"
  local name="${6:-arctic_fan_controller}"
  local verified="${7:-true}"
  local sha
  local manifest_sha
  mkdir -p "${dir}"
  printf '%s\n' "${body}" > "${dir}/arctic_fan_controller.ko"
  sha="$(sha256sum "${dir}/arctic_fan_controller.ko" | awk '{print $1}')"
  printf '%s  %s\n' "${sha}" "arctic_fan_controller.ko" > "${dir}/arctic_fan_controller.ko.sha256"
  manifest_sha="${manifest_sha_override:-${sha}}"
  manifest "${manifest_kernel}" "${manifest_sha}" "${name}" "${verified}" > "${dir}/build-manifest.json"
}

make_release() {
  local kernel="$1"
  make_module_set "${tmp_root}/releases/kernel-${kernel}" "${kernel}" "release-${kernel}"
}

run_loader() {
  env \
    PATH="${tmp_root}/bin:${PATH}" \
    AFC_KERNELRELEASE="${AFC_TEST_KERNEL:-6.18.38-Unraid}" \
    AFC_CACHE_ROOT="${tmp_root}/cache" \
    AFC_TMP_ROOT="${tmp_root}/tmp" \
    AFC_GITHUB_RELEASE_BASE_URL="${tmp_root}/releases" \
    AFC_CURL_CMD="${tmp_root}/bin/curl" \
    AFC_MODINFO_CMD="${tmp_root}/bin/modinfo" \
    AFC_LSMOD_CMD="${tmp_root}/bin/lsmod" \
    AFC_MODPROBE_CMD="${tmp_root}/bin/modprobe" \
    AFC_INSMOD_CMD="${tmp_root}/bin/insmod" \
    AFC_SHA256SUM_CMD="sha256sum" \
    AFC_LOG_SYSLOG=0 \
    AFC_TEST_INSMOD_LOG="${tmp_root}/insmod.log" \
    AFC_TEST_MODPROBE_LOG="${tmp_root}/modprobe.log" \
    "${loader}" >"${tmp_root}/stdout.log" 2>"${tmp_root}/stderr.log"
}

assert_pass() {
  local case_name="$1"
  shift
  setup
  if "$@"; then
    printf 'ok - %s\n' "${case_name}"
  else
    printf 'not ok - %s\n' "${case_name}" >&2
    [ ! -f "${tmp_root}/stderr.log" ] || sed 's/^/# stderr: /' "${tmp_root}/stderr.log" >&2
    [ ! -f "${tmp_root}/insmod.log" ] || sed 's/^/# insmod: /' "${tmp_root}/insmod.log" >&2
    failures=$((failures + 1))
  fi
  teardown
}

assert_fail() {
  local case_name="$1"
  shift
  setup
  if "$@"; then
    printf 'not ok - %s\n' "${case_name}" >&2
    failures=$((failures + 1))
  else
    printf 'ok - %s\n' "${case_name}"
  fi
  teardown
}

test_native_module_available() {
  export AFC_TEST_NATIVE_PATH="/lib/modules/6.18.38-Unraid/kernel/drivers/hwmon/arctic_fan_controller.ko"
  run_loader
  [ ! -s "${tmp_root}/insmod.log" ] && grep -Fxq arctic_fan_controller "${tmp_root}/modprobe.log"
}

test_exact_verified_cached_module() {
  make_module_set "${tmp_root}/cache/modules/6.18.38-Unraid" "6.18.38-Unraid"
  run_loader
  grep -Fq "cache/modules/6.18.38-Unraid/arctic_fan_controller.ko" "${tmp_root}/insmod.log"
}

test_no_cache_valid_release() {
  make_release "6.18.38-Unraid"
  run_loader
  [ -f "${tmp_root}/cache/modules/6.18.38-Unraid/build-manifest.json" ]
  grep -Fq "cache/modules/6.18.38-Unraid/arctic_fan_controller.ko" "${tmp_root}/insmod.log"
}

test_release_missing() {
  ! run_loader
}

test_wrong_sha() {
  make_release "6.18.38-Unraid"
  printf 'bad  arctic_fan_controller.ko\n' > "${tmp_root}/releases/kernel-6.18.38-Unraid/arctic_fan_controller.ko.sha256"
  ! run_loader
}

test_manifest_kernel_mismatch() {
  dir="${tmp_root}/releases/kernel-6.18.38-Unraid"
  make_module_set "${dir}" "6.18.38-Unraid" "body" "6.18.42-Unraid"
  ! run_loader
}

test_manifest_sha_mismatch() {
  dir="${tmp_root}/releases/kernel-6.18.38-Unraid"
  make_module_set "${dir}" "6.18.38-Unraid" "body" "6.18.38-Unraid" "bad"
  ! run_loader
}

test_wrong_vermagic() {
  make_release "6.18.38-Unraid"
  export AFC_TEST_MODULE_VERMAGIC="6.18.42-Unraid"
  ! run_loader
}

test_wrong_alias() {
  make_release "6.18.38-Unraid"
  export AFC_TEST_MODULE_ALIAS="hid:b0003g*v0000DEADp0000BEEF"
  ! run_loader
}

test_kernel_source_not_verified() {
  dir="${tmp_root}/releases/kernel-6.18.38-Unraid"
  make_module_set "${dir}" "6.18.38-Unraid" "body" "6.18.38-Unraid" "" "arctic_fan_controller" "false"
  ! run_loader
}

test_non_native_modinfo_path_ignored() {
  export AFC_TEST_NATIVE_PATH="/boot/config/plugins/arctic-fan-controller/modules/6.18.38-Unraid/arctic_fan_controller.ko"
  make_release "6.18.38-Unraid"
  run_loader
  [ ! -s "${tmp_root}/modprobe.log" ] && grep -Fq "cache/modules/6.18.38-Unraid/arctic_fan_controller.ko" "${tmp_root}/insmod.log"
}

test_stale_cache_previous_kernel() {
  make_module_set "${tmp_root}/cache/modules/6.18.37-Unraid" "6.18.37-Unraid"
  make_release "6.18.38-Unraid"
  run_loader
  grep -Fq "cache/modules/6.18.38-Unraid/arctic_fan_controller.ko" "${tmp_root}/insmod.log"
}

test_module_already_loaded() {
  export AFC_TEST_LOADED=1
  make_release "6.18.38-Unraid"
  run_loader
  [ ! -s "${tmp_root}/insmod.log" ] && [ ! -d "${tmp_root}/cache/modules/6.18.38-Unraid" ]
}

test_network_failure() {
  make_release "6.18.38-Unraid"
  rm -f "${tmp_root}/releases/kernel-6.18.38-Unraid/build-manifest.json"
  ! run_loader
}

test_incomplete_download_no_cache_write() {
  make_release "6.18.38-Unraid"
  rm -f "${tmp_root}/releases/kernel-6.18.38-Unraid/arctic_fan_controller.ko.sha256"
  ! run_loader
  [ ! -d "${tmp_root}/cache/modules/6.18.38-Unraid" ]
}

test_corrupt_cache_redownloads() {
  make_module_set "${tmp_root}/cache/modules/6.18.38-Unraid" "6.18.38-Unraid" "bad-cache"
  printf 'bad  arctic_fan_controller.ko\n' > "${tmp_root}/cache/modules/6.18.38-Unraid/arctic_fan_controller.ko.sha256"
  make_release "6.18.38-Unraid"
  run_loader
  [ -d "${tmp_root}/cache/modules/6.18.38-Unraid" ] && grep -Fq "release-6.18.38-Unraid" "${tmp_root}/cache/modules/6.18.38-Unraid/arctic_fan_controller.ko"
}

test_idempotent_rerun_loaded() {
  make_release "6.18.38-Unraid"
  run_loader
  export AFC_TEST_LOADED=1
  : > "${tmp_root}/insmod.log"
  run_loader
  [ ! -s "${tmp_root}/insmod.log" ]
}

assert_pass "native module available" test_native_module_available
assert_pass "exact verified cached module" test_exact_verified_cached_module
assert_pass "no cache valid release" test_no_cache_valid_release
assert_fail "GitHub release missing" test_release_missing
assert_fail "wrong SHA" test_wrong_sha
assert_fail "manifest kernel mismatch" test_manifest_kernel_mismatch
assert_fail "manifest module SHA mismatch" test_manifest_sha_mismatch
assert_fail "wrong module vermagic" test_wrong_vermagic
assert_fail "wrong module alias" test_wrong_alias
assert_fail "kernel source not verified" test_kernel_source_not_verified
assert_pass "non-native modinfo path ignored" test_non_native_modinfo_path_ignored
assert_pass "stale cache previous kernel ignored" test_stale_cache_previous_kernel
assert_pass "module already loaded" test_module_already_loaded
assert_fail "network failure" test_network_failure
assert_fail "incomplete download" test_incomplete_download_no_cache_write
assert_pass "corrupt cache redownloads" test_corrupt_cache_redownloads
assert_pass "rerun is idempotent when loaded" test_idempotent_rerun_loaded

[ "${failures}" -eq 0 ] || exit 1
