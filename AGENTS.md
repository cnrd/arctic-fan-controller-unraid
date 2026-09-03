# AGENTS.md

Guidance for coding agents working in this repository.

## Project Scope

This repository packages the upstream Linux `arctic_fan_controller` driver as an external Unraid kernel module and provides an Unraid plugin that downloads, verifies, caches, and loads the exact matching module for the running kernel.

The plugin is a kernel-module loader only. Do not add fan curves, PWM policy, temperature-control logic, or a userspace fan controller unless explicitly requested.

## Non-Negotiable Rules

- Keep `driver/arctic_fan_controller.c` byte-identical to the pinned upstream source unless the task explicitly changes the upstream pin.
- Put local compatibility shims outside the vendored driver, such as in `driver/compat.h` and Makefile flags.
- Never introduce force-loading behavior: no `insmod -f`, `modprobe -f`, `--force-vermagic`, or `--force-modversion`.
- Match modules by exact `uname -r` / kernel release only. Do not add fuzzy matching or fallback to nearby kernels.
- The plugin must not compile modules on an Unraid host. It may only download, verify, cache, and load published prebuilt artifacts.
- Native kernel support wins. Treat only `builtin`, `(builtin)`, or paths under `/lib/modules/$KERNELRELEASE/kernel/` as native.
- Do not silently skip integrity checks. SHA256, manifest, module name, vermagic, and HID alias validation are part of the safety model.

## Release Model

- Release tags are named `kernel-<KERNELRELEASE>`, for example `kernel-6.18.38-Unraid`.
- Each complete release must publish:
  - `arctic_fan_controller.ko`
  - `arctic_fan_controller.ko.sha256`
  - `build-manifest.json`
  - `arctic-fan-controller-<KERNELRELEASE>.zip`
- Build manifests must identify the repository commit, exact target kernel, kernel source verification status, upstream driver pin, module metadata, and module SHA256.
- Scheduled builds should skip already-complete releases and should require trusted kernel-source digest data.

## Important Files

- `driver/arctic_fan_controller.c`: vendored upstream driver; do not edit casually.
- `driver/compat.h`: compatibility definitions for building older/newer Unraid kernels without changing the driver.
- `driver/Makefile`: external module build flags and source inclusion.
- `.github/workflows/build.yml`: kernel-specific build, verification, attestation, and release publication.
- `scripts/fetch-kernel.sh`: resolves and verifies kernel build inputs.
- `scripts/prepare-kernel.sh`: prepares the downloaded kernel tree for external module builds.
- `scripts/build-module.sh`: builds `arctic_fan_controller.ko`.
- `scripts/verify-module.sh`: verifies module metadata and target compatibility.
- `plugin/usr/local/sbin/arctic-fan-controller-loader`: Unraid loader, download, cache, and verification logic.
- `plugin/etc/rc.d/rc.arctic-fan-controller`: Unraid service wrapper.
- `arctic-fan-controller.plg`: Unraid plugin metadata and install/remove actions.
- `tests/loader-tests.sh`: shell test harness for loader behavior.

## Validation

Run the smallest relevant checks after changes. For broad changes, use:

```sh
bash -n plugin/usr/local/sbin/arctic-fan-controller-loader plugin/etc/rc.d/rc.arctic-fan-controller tests/loader-tests.sh scripts/*.sh
xmllint --noout arctic-fan-controller.plg
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml")'
tests/loader-tests.sh
git diff --check
```

`shellcheck` is useful when available, but it is not assumed to be installed locally.

## Plugin Safety Expectations

- Loader failure during plugin install or boot should fail safe and leave the module unloaded.
- A missing release for the exact running kernel is not fatal; report it and do not load anything else.
- Corrupt cache entries should be quarantined or replaced only after a verified exact release is available.
- Cache paths must remain kernel-specific under `/boot/config/plugins/arctic-fan-controller/modules/<KERNELRELEASE>`.
- Keep test hooks such as `AFC_*` environment overrides working unless intentionally refactoring the tests with the loader.

## Documentation

- Keep README user-focused: installation, behavior, status, architecture, and safety guarantees.
- Put detailed developer process notes in `docs/` or this file when they are instructions for future agents.
- When changing supported Unraid versions or kernels, update the plugin metadata, README, and release/build documentation together.
