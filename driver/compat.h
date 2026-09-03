/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef ARCTIC_FAN_CONTROLLER_COMPAT_H
#define ARCTIC_FAN_CONTROLLER_COMPAT_H

#include <linux/version.h>

/*
 * Linux 7.2-era DMA/cacheline annotations are not present in Linux 6.12 or
 * 6.18. They are layout/debug annotations only for this driver's embedded HID
 * report buffer, so older kernels can build with no-op definitions.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 2, 0)
#ifndef __dma_from_device_group_begin
#define __dma_from_device_group_begin(...)
#endif
#ifndef __dma_from_device_group_end
#define __dma_from_device_group_end(...)
#endif
#endif

#endif /* ARCTIC_FAN_CONTROLLER_COMPAT_H */
