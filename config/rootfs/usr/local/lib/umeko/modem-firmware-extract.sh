#!/bin/sh
# Extract WiFi/modem firmware (wcnss.*, mba.mbn, modem.*) from the phone's own
# modem partition into /lib/firmware. The files are Qualcomm proprietary and
# cannot be redistributed in the image; every device carries them in its
# modem partition, so we copy them over on-device at boot instead.
# (The legacy KlipperPhonesLinux images ship the same files in /lib/firmware.)
set -e

[ -f /lib/firmware/wcnss.mdt ] && exit 0

MODEM=/dev/disk/by-partlabel/modem
[ -e "$MODEM" ] || { echo "modem partition not found"; exit 0; }

MNT=/mnt/modem-firmware
mkdir -p "$MNT"
mount -o ro -t vfat "$MODEM" "$MNT"
# Files live in image/ on most qcom modem partitions, sometimes at the root.
SRC="$MNT/image"
[ -d "$SRC" ] || SRC="$MNT"
cp -n "$SRC"/wcnss.* "$SRC"/mba.mbn "$SRC"/modem.* /lib/firmware/ 2>/dev/null || true
umount "$MNT"

if [ -f /lib/firmware/wcnss.mdt ]; then
    echo "modem/wifi firmware installed from modem partition"
    # The wcnss remoteproc may already have failed to probe this boot;
    # (re)load the WiFi stack so it works without a reboot where possible.
    modprobe qcom_wcnss_ctrl 2>/dev/null || true
    modprobe wcn36xx 2>/dev/null || true
fi
