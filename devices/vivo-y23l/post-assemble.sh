#!/bin/bash
# vivo Y23L post-assemble hook (runs in the chroot, after the base setup).
set -e

# Mount the extlinux bootfs at /boot: kernel/dtbs/extlinux.conf live there,
# mounting it lets the running system inspect and update them.
# BOOTFS_UUID is fixed in config/base.env and written into the bootfs image
# by pack_extlinux.sh (mke2fs -U).
echo "UUID=${BOOTFS_UUID} /boot ext2 defaults 0 2" >> /etc/fstab

# TEMPORARY: same build-time firmware fetch as the wt88047 hook (see that
# file for the rationale), gated on BUNDLE_FIRMWARE=1 (local builds only —
# CI must not ship proprietary firmware). Drop this block once on-device
# extraction via umeko-modem-firmware.service is fixed.
if [ "${BUNDLE_FIRMWARE:-0}" = "1" ]; then
    FW_URL="https://github.com/umeiko/umeko-linux-phones-firmwares/releases/download/msm8916-20260907/msm8916-firmware.tar.gz"
    FW_SHA256="bfc8089a02b3a808d323f0ea5f12aa9d8b702faf0a25af65e7463ffc411f84a1"
    wget -q "$FW_URL" -O /tmp/msm8916-firmware.tar.gz
    echo "$FW_SHA256  /tmp/msm8916-firmware.tar.gz" | sha256sum -c -
    mkdir -p /lib/firmware
    tar xzf /tmp/msm8916-firmware.tar.gz -C /lib/firmware/
    rm -f /tmp/msm8916-firmware.tar.gz
fi
