# ARCTIC Fan Controller Backport For Unraid

This repository is a temporary backport project for the upstream Linux
`arctic_fan_controller` hwmon driver for the ARCTIC Fan Controller
ACFAN00351A.

The upstream driver targets Linux 7.2 and supports a USB HID hwmon device with
10 RPM inputs and 10 independently writable PWM outputs. This project keeps the
upstream source as close as possible while building an out-of-tree module for
specific Unraid kernel releases.

Do not use this repository to alter an Unraid server yet. The current milestone
only prepares source, documentation, scripts, and GitHub Actions build plumbing.

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

The driver APIs used by the upstream driver are present in Linux 6.12 and 6.18
based on header comparison against upstream Linux tags. The likely source-level
compatibility issue is the newer DMA/cacheline annotation used around the HID
OUT report buffer:

- `__dma_from_device_group_begin()`
- `__dma_from_device_group_end()`

These annotations exist in Linux 7.2-era headers but are absent from Linux 6.12
and Linux 6.18 headers checked during this milestone. The backport therefore
adds `driver/compat.h`, included once by the driver, which defines those macros
as no-ops only when building against kernels older than 7.2. This preserves the
upstream allocation strategy while allowing older kernel headers to compile.

Every source difference from the pinned upstream driver is tracked in:

- `patches/0001-backport-arctic-fan-controller-compat.patch`

No behavior change is intended by the compatibility layer.

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

This repository's scripts support both directions but currently require an
explicit source mode:

- `UNRAID_KERNEL_SOURCE_MODE=local`: use a pre-provided kernel build tree at `UNRAID_KERNEL_TREE`
- `UNRAID_KERNEL_SOURCE_MODE=ich777`: download the matching `linux-<kernelrelease>.tar.xz` from `ich777/unraid_kernel` releases, or copy `/usr/src` from an explicitly supplied `ICH777_UNRAID_KERNEL_IMAGE`
- `UNRAID_KERNEL_SOURCE_MODE=official-zip`: reserved until exact official Unraid source/patch extraction behavior is pinned for the chosen release

The scripts validate the required files before building. They do not fake
`Module.symvers`, disable modversions, force load modules, or substitute generic
kernel headers.

For Unraid `7.3.2`, the exact `ich777/unraid_kernel` release exists:

- release: `https://github.com/ich777/unraid_kernel/releases/tag/6.18.38-Unraid`
- asset: `linux-6.18.38-Unraid.tar.xz`
- SHA256: `b336c66bf1d7ee2cedba88e8be2124b2256c94476b1d1c944518ce8d6bcf37da`
- release body: `Pre-compiled Unraid Kernel v6.18.38 gcc_14.2.0 by ich777`

The tarball was inspected and contains the required build inputs, including
`.config`, `Module.symvers`, `include/generated/autoconf.h`,
`include/config/kernel.release`, and `scripts/mod/modpost`.

## GitHub Actions

`.github/workflows/build.yml` runs only on Linux x86-64 runners. It is matrix
ready and currently contains placeholder target values. For each configured
target it will:

- install build and metadata tools
- fetch or stage the matching Unraid kernel build tree via `scripts/fetch-kernel.sh`
- run `scripts/prepare-kernel.sh`
- build only the external `arctic_fan_controller.ko` via `scripts/build-module.sh`
- verify compile-time metadata via `scripts/verify-module.sh`
- upload `.ko`, `modinfo`, `file`, and build logs as artifacts

Compile-time verification is not runtime verification. A passing workflow only
means the module compiled and has plausible metadata for the target kernel. It
does not mean it will load on Unraid or operate the hardware.

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

## Information Needed From Current Unraid Machine

Before attempting the first exact-target build, collect this information from
the Unraid machine without changing boot files or loading this driver:

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
