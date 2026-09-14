#!/bin/bash
# cancro post-assemble hook — runs inside the qemu-arm chroot at the end of
# assemble.sh, after the base system, kernel modules and the shared
# config/rootfs overlay are in place.
set -e

# The overlay may lose executable bits when the git working tree lives on a
# Windows checkout, so fix permissions explicitly.
chmod 644 /etc/systemd/system/*.service /etc/modprobe.d/*.conf
chmod 755 /usr/local/lib/umeko/*.sh /usr/local/lib/umeko/webssh /usr/local/sbin/*.sh

# Mount the extlinux bootfs at /boot — NOTE: cancro boots via a mkbootimg
# boot.img (pack.sh), not the extlinux scan, so /boot is just the kernel
# build residue from initramfs generation; keep fstab empty for cancro.

# Same service set as wt88047 (see config/rootfs). webssh comes from the
# vendored armhf binary (see devices/cancro.env), so autowebssh is enabled
# here too.
systemctl enable \
    umeko-modem-firmware.service \
    usb-gadget.service \
    ncm-serial.service \
    autoresize.service \
    auto_rmi4_reload.service \
    autowebssh.service \
    autocanup.service
