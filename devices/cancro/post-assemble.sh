#!/bin/bash
# cancro post-assemble hook — runs inside the qemu-arm chroot at the end of
# assemble.sh, after the base system, kernel modules and the shared
# config/rootfs overlay are in place.
set -e

# The overlay may lose executable bits when the git working tree lives on a
# Windows checkout, so fix permissions explicitly.
chmod 644 /etc/systemd/system/*.service /etc/modprobe.d/*.conf
chmod 755 /usr/local/lib/umeko/*.sh

# Mount the extlinux bootfs at /boot: kernel/dtbs/extlinux.conf live there,
# mounting it lets the running system inspect and update them.
echo "UUID=${BOOTFS_UUID} /boot ext2 defaults 0 2" >> /etc/fstab

# Same service set as wt88047 (see config/rootfs), EXCEPT autowebssh:
# there is no armhf webssh binary yet (WIP — see devices/cancro.env).
systemctl enable \
    umeko-modem-firmware.service \
    usb-gadget.service \
    autottyGS0.service \
    autoresize.service \
    auto_rmi4_reload.service \
    autocanup.service
