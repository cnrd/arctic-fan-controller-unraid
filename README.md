# ARCTIC Fan Controller for Unraid

Provide native Linux `hwmon` support for the **ARCTIC Fan Controller (ACFAN00351A)** on Unraid systems whose kernel does not yet include the upstream Linux driver.

This project packages the **unmodified upstream Linux `arctic_fan_controller` driver** as an external kernel module, automatically builds it for supported Unraid kernel releases, publishes versioned GitHub Releases, and provides an Unraid plugin that automatically downloads, verifies, caches, and loads the correct module for your system.

---

# Installation

> [!WARNING]
> **Current project status: Beta**
>
> The module has been successfully built, verified, loaded, and unloaded on a real
> Unraid 7.3.2 (`6.18.38-Unraid`) server.
>
> Runtime validation with the physical ARCTIC Fan Controller is still pending.

## Install the plugin

In the Unraid web interface, navigate to:

```text
Plugins
→ Install Plugin
```

Paste the following URL into the **Install Plugin** field:

```text
https://github.com/cnrd/arctic-fan-controller-unraid/raw/refs/heads/main/arctic-fan-controller.plg
```

Then click **Install**.

The plugin automatically:

- Detects the exact running kernel using `uname -r`
- Checks whether Unraid already provides a native `arctic_fan_controller`
- Downloads the matching external module if required
- Verifies:
  - SHA256 checksum
  - Build manifest
  - Module metadata
  - Vermagic
- Caches the verified module on the flash drive
- Loads the module

No manual compilation is required.

If no matching module has been published for the running kernel, the plugin safely leaves the driver unloaded.

---

# Updating Unraid

Nothing special is required.

After every reboot the plugin automatically:

1. Detects the current kernel.
2. Prefers the native kernel driver if available.
3. Otherwise looks for a cached module matching the exact kernel.
4. Downloads and verifies the matching release if necessary.
5. Loads the verified module.

The plugin **never**:

- loads a module built for another kernel
- ignores vermagic
- skips checksum verification
- force-loads an incompatible module

---

# What this project is

This project provides:

- the upstream Linux kernel driver
- automated per-kernel builds
- GitHub Releases
- automatic Unraid integration
- standard Linux `hwmon` support

---

# What this project is **not**

This project does **not** provide:

- fan curves
- HDD temperature control
- CPU temperature control
- automatic PWM policies
- a replacement for IPMI fan control
- a userspace fan controller

It only provides the kernel driver.

Any userspace software can then use the standard Linux `hwmon` interface exposed by the driver.

---

# Current Status

## Verified

- ✅ Upstream Linux driver imported unchanged
- ✅ Driver builds against Unraid 7.3.x kernels
- ✅ GitHub Actions automatically build kernel-specific modules
- ✅ Automatic GitHub Releases
- ✅ Automatic SHA256 verification
- ✅ Automatic build provenance generation
- ✅ Unraid plugin implemented
- ✅ Exact kernel matching
- ✅ Automatic module download
- ✅ Automatic cache management
- ✅ Module successfully loads on a real Unraid server
- ✅ Module successfully unloads on a real Unraid server

## Pending

- ⏳ Hardware validation
- ⏳ USB HID binding verification
- ⏳ `hwmon` device creation
- ⏳ RPM validation
- ⏳ PWM validation
- ⏳ Hot-plug testing
- ⏳ USB disconnect/reconnect testing

At the current stage the project should be considered:

> **Compile-tested, package-tested, load-tested and plugin-tested.**

Hardware functionality is awaiting arrival of the ARCTIC controller.

---

# Supported Hardware

Current target:

- **ARCTIC Fan Controller**
- Model: **ACFAN00351A**

The driver exposes the controller through the standard Linux `hwmon` subsystem.

Expected interface:

```
fan1_input ... fan10_input
pwm1       ... pwm10
```

Expected HID alias:

```
hid:b0003g*v00003904p0000F001
```

---

# Architecture

```
                  Linux upstream
                         │
                         ▼
       driver/arctic_fan_controller.c
                         │
               Repository patches
                         │
                         ▼
             GitHub Actions CI
                         │
                         ▼
      Kernel-specific GitHub Releases
                         │
                         ▼
              Unraid Plugin
                         │
                         ▼
       Exact verified kernel module
                         │
                         ▼
              Linux hwmon subsystem
```

The project intentionally separates:

- upstream driver
- repository patches applied in the build staging directory
- build system
- release pipeline
- Unraid integration

---

# Repository Layout

```
.
├── driver/
│   └── arctic_fan_controller.c
│
├── plugin/
│   ├── plugin files
│   └── loader scripts
│
├── patches/
│   └── local driver patches
│
├── scripts/
│   ├── fetch-kernel.sh
│   ├── prepare-kernel.sh
│   ├── build-module.sh
│   └── verify-module.sh
│
├── .github/
│   └── workflows/
│
├── docs/
│
└── README.md
```

---

# Build System

GitHub Actions automatically builds the module for supported Unraid kernels.

For every build the workflow:

1. Determines the target kernel.
2. Downloads the matching prepared kernel build tree.
3. Verifies kernel source integrity.
4. Applies repository driver patches in an isolated staging directory.
5. Builds the external module.
6. Verifies:
   - module metadata
   - architecture
   - vermagic
   - USB alias
7. Generates build metadata, including applied patch paths and SHA256 hashes.
8. Publishes a GitHub Release.

Releases are keyed by the exact kernel release:

```
kernel-6.18.38-Unraid
```

---

# Release Contents

Each release contains:

- `arctic_fan_controller.ko`
- `arctic_fan_controller.ko.sha256`
- `build-manifest.json`
- `arctic-fan-controller-<kernel>.zip`

The ZIP additionally contains build logs and verification outputs.

---

# Build Manifest

Each release includes a machine-readable manifest describing:

- project commit
- build timestamp
- target kernel
- kernel source
- kernel source verification
- upstream driver commit
- applied driver patches and their SHA256 hashes
- module SHA256
- vermagic
- architecture
- aliases

This allows every published module to be traced back to the exact source and build inputs.

---

# Plugin Behaviour

The plugin follows this boot sequence:

```
Boot
 │
 ▼
Native driver available?
 │
 ├── Yes
 │      ▼
 │   modprobe
 │      ▼
 │     Done
 │
 └── No
        ▼
Cached module exists?
        │
        ├── Yes
        │
        │ Verify
        │
        ▼
      Load module
        │
        └── No
               ▼
Download matching release
               │
               ▼
Verify
 • SHA256
 • Manifest
 • Vermagic
 • Module metadata
               │
               ▼
Cache to flash
               │
               ▼
Load module
```

The plugin always matches the **exact** kernel reported by:

```
uname -r
```

It never falls back to another kernel version.

---

# Native Driver Transition

This repository exists only until Unraid ships the upstream Linux driver.

When that happens the plugin will simply detect the native module and use it instead of downloading an external one.

No migration should be required.

---

# Upstream Source

Pinned upstream driver:

Repository:

```
https://github.com/torvalds/linux
```

Source:

```
drivers/hwmon/arctic_fan_controller.c
```

Pinned commit:

```
e28d0c73d4d7adc9cd3747d81fdc7338217f9a0c
```

The goal of this project is to keep the driver source identical to upstream whenever possible.

---

# Documentation

Additional developer documentation is available under `docs/`.

Suggested topics include:

- build system
- plugin internals
- CI pipeline
- development notes
- compatibility notes

The README intentionally focuses on project overview and usage.

---

# Roadmap

- ✅ Import upstream driver
- ✅ Automated kernel builds
- ✅ GitHub Releases
- ✅ Build provenance
- ✅ Unraid plugin
- ✅ Automatic module loading
- ⏳ Hardware validation
- ⏳ Community testing
- ⏳ Native-driver retirement

---

# License

The kernel driver remains subject to the upstream Linux kernel licensing (GPL).

Project-specific scripts, build automation and plugin infrastructure are licensed separately as defined by this repository.
