# ARCTIC Fan Controller Backport For Unraid

This repository is a temporary backport project for the upstream Linux
`arctic_fan_controller` hwmon driver for the ARCTIC Fan Controller
ACFAN00351A.

The upstream driver targets Linux 7.2 and supports a USB HID hwmon device with
10 RPM inputs and 10 independently writable PWM outputs. This project keeps the
upstream source as close as possible while building an out-of-tree module for
specific Unraid kernel releases.

Do not use this repository for fan-control policy yet. The external module has
loaded and unloaded cleanly on a real Unraid 7.3.2 / `6.18.38-Unraid` server,
but actual ARCTIC USB hardware binding and PWM behavior have not been validated.

## Upstream Source

Authoritative upstream source is the Linux kernel tree:

- Driver: `drivers/hwmon/arctic_fan_controller.c`
- Kconfig entry: `drivers/hwmon/Kconfig`, `SENSORS_ARCTIC_FAN_CONTROLLER`
- Makefile entry: `drivers/hwmon/Makefile`, `obj-$(CONFIG_SENSORS_ARCTIC_FAN_CONTROLLER) += arctic_fan_controller.o`
- Documentation: `Documentation/hwmon/arctic_fan_controller.rst`

Pinned upstream commit:

- Commit: `e28d0c73d4d7adc9cd3747d81fdc7338217f9a0c`
- Subject: `hwmon: add driver for ARCTIC Fan Controller`
- Author: Aureo Serrano de Souza `<aureo.serrano@arctic.de>`
- Committer: Guenter Roeck `<linux@roeck-us.net>`
- Link: `https://github.com/torvalds/linux/commit/e28d0c73d4d7adc9cd3747d81fdc7338217f9a0c`
- Mailing-list link: `https://lore.kernel.org/r/20260508064405.38676-1-aureo.serrano@arctic.de`
- Merge context: included in Linus' `hwmon-for-v7.2` pull merge `fc2ce3ee106f2d53eb344f5c4963c897bbb21634`

The driver source in `driver/arctic_fan_controller.c` preserves the upstream
SPDX, copyright-relevant comments, author, and license metadata.

## Device And Sysfs Interface

The upstream hwmon documentation identifies the supported USB HID device as:

- VID: `0x3904`
- PID: `0xF001`
- Expected module alias: `hid:b0003g*v00003904p0000F001`

Expected hwmon attributes after successful runtime load with hardware attached:

- `fan1_input` through `fan10_input`
- `pwm1` through `pwm10`

The device does not support reading current PWM state at probe. The driver
caches successfully written PWM values and initializes the cache to `0`.

## Driver Dependencies

Kernel configuration dependencies from upstream Kconfig:

- `CONFIG_HWMON`
- `CONFIG_HID`
- `CONFIG_USB_HID`

The module depends on exported symbols from HID, USB HID transport, hwmon, and
standard kernel facilities used by external modules. Exact symbol CRCs must
come from the matching Unraid kernel build tree when `CONFIG_MODVERSIONS=y`.

Major kernel APIs used by the driver:

- HID: `hid_is_usb`, `hid_parse`, `hid_hw_start`, `hid_hw_stop`, `hid_hw_open`, `hid_hw_close`, `hid_device_io_start`, `hid_device_io_stop`, `hid_hw_output_report`, `hid_get_drvdata`, `hid_set_drvdata`, `module_hid_driver`, `HID_USB_DEVICE`
- hwmon: `hwmon_device_register_with_info`, `hwmon_device_unregister`, `HWMON_CHANNEL_INFO`, `struct hwmon_ops`, `struct hwmon_chip_info`
- synchronization: `spin_lock_irqsave`, `spin_unlock_irqrestore`, `struct completion`, `init_completion`, `reinit_completion`, `complete`, `wait_for_completion_timeout`
- helpers: `devm_kzalloc`, `IS_ERR`, `PTR_ERR`, `clamp_val`, `DIV_ROUND_CLOSEST`, `msecs_to_jiffies`, `get_unaligned_le16`

## Compatibility Findings

The supported Unraid 7.3.x targets are:

- Unraid `7.3.0`: `6.18.29-Unraid`
- Unraid `7.3.1`: `6.18.33-Unraid`
- Unraid `7.3.2`: `6.18.38-Unraid`

The exact `ich777/unraid_kernel` trees for newer 7.3 kernels contain the upstream
DMA/cacheline annotations around the embedded HID OUT report buffer:

- `__dma_from_device_group_begin()`
- `__dma_from_device_group_end()`

Those annotations are not runtime functions. They expand to cacheline group
markers plus `ARCH_DMA_MINALIGN` alignment so the DMA buffer does not share
cachelines with adjacent CPU-written fields on platforms with DMA-incoherent
caches.

These annotations are not present in the `6.18.29-Unraid` source used by Unraid
7.3.0. `driver/compat.h` defines missing annotation macros as no-ops at external
module build time, while `driver/arctic_fan_controller.c` remains byte-identical
to the pinned upstream file.

## Unraid Kernel Build Requirements

An external module that actually loads on Unraid must be built against the exact
kernel build inputs for the target Unraid release. Generic upstream headers are
not sufficient if they do not reproduce Unraid's release string, compiler flags,
configuration, patches, and symbol CRCs.

Required inputs for each target:

- exact Unraid release, for example `6.x.y`
- exact `uname -r` / `KERNELRELEASE` string from that Unraid release
- the matching kernel source tree after Unraid patches are applied
- the matching Unraid kernel `.config`
- `Module.symvers` from the matching configured/built kernel when `CONFIG_MODVERSIONS=y`
- generated headers from `make modules_prepare`
- compiler/toolchain compatible with the one used to build the target kernel

Relevant existing approaches found during research:

- `ich777/unraid_kernel` publishes precompiled Unraid kernel releases and OCI containers beginning with Unraid 6.12.0. Its container prepares `/lib/modules/$(uname -r)/build` for driver compilation and emphasizes selecting the image that matches the Unraid release/toolchain.
- `games-on-whales/unraid-module-builder` downloads the official Unraid zip, extracts `bzroot` and `bzfirmware`, locates `/usr/src/linux-*` inside the extracted image, downloads the matching upstream kernel tarball from kernel.org, copies Unraid config/patch material from the extracted image into that source tree, applies patches, runs `make oldconfig`, builds the kernel/modules, and copies requested modules.

Additional check against
`bootable-unraid-installer` release `Installer-7.3.2-sp.1`:

- bundled installer asset: `unraid-installer-7.3.2-sp.1-bundled.img.zip`
- asset SHA256 verified: `7a027e6e2a3da93129d7f54e9dfeed0bd43ac778f7047fe52943644cab4a495f`
- disk image contains `zips/unRAIDServer-7.3.2-x86_64.zip`
- seeded metadata marks redistribution as approved and identifies Unraid `7.3.2`
- bundled OS zip SHA256 from seeded metadata: `9ecf63726f69b8b11706e87bbcbfbea8ac8863bfed0867a1f9dcc272dee21420`
- bundled OS zip contains `bzimage`, `bzroot`, `bzmodules`, and firmware/runtime files
- `bzimage` reports kernel `6.18.38-Unraid`
- extracted `bzroot` has `/lib/modules/6.18.38-Unraid/build` as a symlink to `/usr/src/linux-6.18.38-Unraid`
- neither extracted `bzroot` nor `bzmodules` contains `/usr/src/linux-6.18.38-Unraid`
- no `.config` or `Module.symvers` was found in the installer/runtime images during this inspection

Conclusion: the official 7.3.2 installer release is useful for verifying the
target runtime kernel and shipped module set, but it does not by itself provide
the prepared kernel build tree required for exact out-of-tree module builds.

This repository's scripts require an explicit source mode:

- `UNRAID_KERNEL_SOURCE_MODE=local`: use a pre-provided kernel build tree at `UNRAID_KERNEL_TREE`
- `UNRAID_KERNEL_SOURCE_MODE=ich777`: download the matching `linux-<kernelrelease>.tar.xz` from `ich777/unraid_kernel` releases, or copy `/usr/src` from an explicitly supplied `ICH777_UNRAID_KERNEL_IMAGE`

`official-zip` is intentionally blocked in the scripts. The inspected Unraid
7.3.2 installer/runtime images verify the target runtime kernel, but they do not
contain `/usr/src/linux-*`, `.config`, or `Module.symvers`, so they are not an
exact external-module build source by themselves.

The scripts validate the required files before building. They do not fake
`Module.symvers`, disable modversions, force load modules, or substitute generic
kernel headers.

For Unraid 7.3.x, exact `ich777/unraid_kernel` releases exist:

- `6.18.29-Unraid`: `81467df4642d907aa11f0266596df1eaaf98666a1190d886629afb2ba0bfe5db`
- `6.18.33-Unraid`: `768c0bd830f8d56b1028714d25e6a2ceeb5e0ec2ba9eba295db1236734ec6cbb`
- `6.18.38-Unraid`: `b336c66bf1d7ee2cedba88e8be2124b2256c94476b1d1c944518ce8d6bcf37da`

The tarballs were inspected by the workflow and contain the required build inputs, including
`.config`, `Module.symvers`, `include/generated/autoconf.h`,
`include/config/kernel.release`, and `scripts/mod/modpost`.

## GitHub Actions

`.github/workflows/build.yml` runs on GitHub's Ubuntu x86-64 runners. It can be
run manually for a specific `KERNELRELEASE`, and it also polls
`ich777/unraid_kernel` every six hours for the latest published Unraid kernel
release.

For each target it will:

- install build and metadata tools
- fetch or stage the matching Unraid kernel build tree via `scripts/fetch-kernel.sh`
- record kernel-source provenance and SHA256 verification status in `build/kernel-source.json`
- verify `driver/arctic_fan_controller.c` is byte-identical to the pinned upstream Linux source
- run `scripts/prepare-kernel.sh`
- build only the external `arctic_fan_controller.ko` via `scripts/build-module.sh`
- verify compile-time metadata via `scripts/verify-module.sh`
- record `modinfo`, `file`, `readelf -h`, undefined-symbol, modversion-section, runner-kernel, and module-vermagic output
- generate `build-manifest.json` with repository, target, upstream-driver, kernel-source, module checksum, and compile-only verification metadata
- package `.ko`, metadata, checksums, provenance JSON, and build logs as artifacts
- publish or update a repository release named `kernel-<KERNELRELEASE>`
- publish GitHub artifact attestations for the ZIP, `.ko`, `.ko.sha256`, and `build-manifest.json`

Scheduled runs are idempotent only when the latest `ich777/unraid_kernel` release
already has a complete release asset set:

- `arctic-fan-controller-<KERNELRELEASE>.zip`
- `arctic_fan_controller.ko`
- `arctic_fan_controller.ko.sha256`
- `build-manifest.json`

Scheduled `ich777` builds fail if GitHub does not expose a SHA256 digest for the
selected kernel tarball. Manual runs can rebuild an existing release and upload
replacement assets with `--clobber`; a manual SHA256 override is optional but
recorded when supplied.

Compile-time verification is not hardware verification. A passing workflow means
the exact vendored upstream driver compiled as an external module against the
selected exact kernel build inputs, and that the produced `.ko` has expected
static metadata. The `6.18.38-Unraid` module has also been manually tested to
load and unload cleanly on a real Unraid 7.3.2 server without the ARCTIC device
attached. It does not prove hardware binding or PWM operation.

## Unraid Plugin Loader

`arctic-fan-controller.plg` is a minimal Unraid 7 plugin that installs a safe
module loader. It does not compile modules on Unraid and does not implement fan
curves, PWM writes, temperature polling, or any userspace fan-control policy.
The plugin declares Unraid `7.3.0` as its minimum supported version because this
project publishes external modules for all documented 7.3.x kernels. Older 7.2.x
kernels are not currently supported by the unchanged upstream driver source.

The plugin-managed persistent cache is:

```text
/boot/config/plugins/arctic-fan-controller/
  modules/
    <KERNELRELEASE>/
      arctic_fan_controller.ko
      arctic_fan_controller.ko.sha256
      build-manifest.json
```

The live boot/manual commands installed by the plugin are recreated into the
Unraid runtime filesystem on plugin install and boot:

- `/usr/local/sbin/arctic-fan-controller-loader`
- `/etc/rc.d/rc.arctic-fan-controller`

Manual retry command after boot:

```sh
/usr/local/sbin/arctic-fan-controller-loader
```

Status command:

```sh
/etc/rc.d/rc.arctic-fan-controller status
```

Loader flow:

```text
Unraid boot
  |
  v
native module available?
  | yes -> modprobe arctic_fan_controller -> done
  |
  no
  v
exact verified cache available?
  | yes -> insmod cached arctic_fan_controller.ko -> done
  |
  no
  v
download exact kernel release assets
  |
  v
SHA + manifest + vermagic + alias valid?
  | no -> fail safely, leave driver unloaded
  |
  yes
  v
cache under modules/<uname -r>/
  |
  v
insmod cached arctic_fan_controller.ko
```

Native driver preference is feature-based. The loader checks `modinfo -k
$(uname -r) -n arctic_fan_controller` and only treats paths under
`/lib/modules/$(uname -r)/kernel/` or built-in module responses as native. A
cached or plugin-managed external module is not considered native. If native
support exists, the loader uses normal `modprobe arctic_fan_controller`, skips
downloads, and leaves external cached modules alone.

External module resolution is exact-string only. The loader uses `uname -r` as
the compatibility key and downloads only these deterministic URLs:

```text
https://github.com/cnrd/arctic-fan-controller-unraid/releases/download/kernel-<KERNELRELEASE>/arctic_fan_controller.ko
https://github.com/cnrd/arctic-fan-controller-unraid/releases/download/kernel-<KERNELRELEASE>/arctic_fan_controller.ko.sha256
https://github.com/cnrd/arctic-fan-controller-unraid/releases/download/kernel-<KERNELRELEASE>/build-manifest.json
```

There is no fallback to nearby kernels, no suffix stripping, and no force-load
path. The loader never uses `insmod -f`, `modprobe -f`, `--force-vermagic`, or
`--force-modversion`.

Before caching or loading an external module, the loader verifies:

- `arctic_fan_controller.ko.sha256` contains a valid SHA256 for `arctic_fan_controller.ko`
- actual module SHA256 matches the checksum file
- `build-manifest.json` is valid JSON
- `schema_version == 1`
- `target.kernelrelease == uname -r`
- `module.file == arctic_fan_controller.ko`
- `module.name == arctic_fan_controller`
- `module.sha256 == actual module SHA256`
- `kernel_source.sha256_verified == true`
- `modinfo -F name == arctic_fan_controller`
- first field of `modinfo -F vermagic == uname -r`
- `modinfo -F alias` contains `hid:b0003g*v00003904p0000F001`

Downloads are staged under `/tmp/arctic-fan-controller/` with `mktemp -d` and
are copied into flash cache only after all verification passes. Existing valid
caches are re-verified on every invocation before loading. If a cache for the
running kernel fails verification, it is quarantined with a `.invalid.<timestamp>`
suffix and the loader attempts a clean exact-kernel download. If the network is
unavailable or the exact release does not exist yet, the loader logs a clear
message and exits nonzero for manual runs; the plugin install/boot wrapper logs
the failure and continues safely so Unraid startup is not broken.

The GitHub repository/release base URL is configurable for tests with
`AFC_GITHUB_RELEASE_BASE_URL`. Other test overrides include `AFC_KERNELRELEASE`,
`AFC_CACHE_ROOT`, `AFC_TMP_ROOT`, command path overrides, and `AFC_DRY_RUN=1`.
These do not disable production verification.

Uninstall removes plugin-managed live files and the persistent cache directory,
but it does not automatically unload `arctic_fan_controller`. If the controller
is actively cooling hardware, unloading the driver during uninstall could be
unsafe. Reboot or run `rmmod arctic_fan_controller` manually only after deciding
that is safe.

Plugin updates preserve valid kernel-module caches by default because the cache
is separate from the live loader files. Caches are only replaced when missing,
kernel-specific, or failing verification.

Trust chain:

```text
GitHub repository
  -> GitHub Actions build
  -> kernel-specific release
  -> SHA256 + build manifest
  -> plugin verifies exact kernel/module
  -> load
```

The loader downloads only the known module, checksum, and manifest artifacts. It
does not source, evaluate, or execute files from GitHub releases.

## Future Runtime Test Plan

Do not run this until an exact target module has been built and you are ready
for a manual, non-forced test on Unraid. Do not automatically write PWM values
during the first load test.

```sh
uname -r
insmod ./arctic_fan_controller.ko
dmesg | tail -100
lsmod | grep arctic
find /sys/class/hwmon -maxdepth 2 -type f
```

Expected hardware-visible files include `fan1_input` through `fan10_input` and
`pwm1` through `pwm10` after the controller is attached and the driver binds.

## Native Driver Transition

This backport is temporary. When Unraid ships a kernel with the native upstream
driver, future installer/plugin logic should prefer:

```sh
modprobe arctic_fan_controller
```

The backported module should only be used when the native module is absent. No
installer or plugin is implemented in this milestone.

## Runtime Information Collection

Before attempting the first runtime load test, collect this information from the
Unraid machine without changing boot files or loading this driver:

```sh
uname -a
uname -r
cat /etc/unraid-version
zcat /proc/config.gz > /boot/config-current-kernel.txt
grep -E '^(CONFIG_MODVERSIONS|CONFIG_MODULE_SIG|CONFIG_HID|CONFIG_USB_HID|CONFIG_HWMON)=' /proc/config.gz
modinfo hid
modinfo usbhid
modinfo hwmon
ls -l /usr/src /lib/modules/$(uname -r) /lib/modules/$(uname -r)/build 2>&1
test -f /usr/src/linux-$(uname -r)/Module.symvers && ls -l /usr/src/linux-$(uname -r)/Module.symvers
test -f /lib/modules/$(uname -r)/build/Module.symvers && ls -l /lib/modules/$(uname -r)/build/Module.symvers
```

If `/usr/src/linux-*` or `/lib/modules/$(uname -r)/build` exists, copy the file
listing and checksums only at first:

```sh
find /usr/src /lib/modules/$(uname -r) -maxdepth 3 -type f \( -name '.config' -o -name 'Module.symvers' -o -name 'include' -o -name 'Makefile' \) -print 2>/dev/null
sha256sum /proc/config.gz 2>/dev/null
```
