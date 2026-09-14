#!/bin/bash
# wt88047 post-assemble hook — runs inside the qemu-aarch64 chroot at the end
# of assemble.sh, after the base system, kernel modules and the rootfs/
# overlay are in place. Device env vars (DEVICE_CODENAME, DEFAULT_USER, ...)
# are passed in the environment.
set -e

# The overlay may lose executable bits when the git working tree lives on a
# Windows checkout, so fix permissions explicitly.
chmod 644 /etc/systemd/system/*.service /etc/modprobe.d/*.conf
chmod 755 /usr/local/lib/umeko/*.sh /usr/local/sbin/*.sh

# Services adopted from https://gitee.com/meiziyang2023/umeko-env-init
# (plus umeko-modem-firmware, which pulls the WiFi/modem firmware from the
# phone's own modem partition; ttyGS0/usb0 come from the configfs gadget
# created by usb-gadget.service, with ncm-serial.service setting the usb0
# address and attaching agetty — proven on real vivo hardware).
systemctl enable \
    umeko-modem-firmware.service \
    usb-gadget.service \
    ncm-serial.service \
    autoresize.service \
    auto_rmi4_reload.service \
    autowebssh.service \
    autocanup.service

# TEMPORARY: fetch modem/WiFi firmware from the firmwares repo release at
# build time — only when BUNDLE_FIRMWARE=1 (local builds; CI runs without it
# so public artifacts never contain proprietary firmware). On-device
# auto-extract (umeko-modem-firmware.service, from the phone's modem
# partition) does not work on this device — partition layout incompatible.
# Once extraction is fixed, drop this block and rely on it.
# NOTE: Qualcomm proprietary firmware — images containing it must NOT be
# published as public releases/CI artifacts.
if [ "${BUNDLE_FIRMWARE:-0}" = "1" ]; then
    FW_URL="https://github.com/umeiko/umeko-linux-phones-firmwares/releases/download/msm8916-20260907/msm8916-firmware.tar.gz"
    FW_SHA256="bfc8089a02b3a808d323f0ea5f12aa9d8b702faf0a25af65e7463ffc411f84a1"
    wget -q "$FW_URL" -O /tmp/msm8916-firmware.tar.gz
    echo "$FW_SHA256  /tmp/msm8916-firmware.tar.gz" | sha256sum -c -
    mkdir -p /lib/firmware
    tar xzf /tmp/msm8916-firmware.tar.gz -C /lib/firmware/
    rm -f /tmp/msm8916-firmware.tar.gz
fi
