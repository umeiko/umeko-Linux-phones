#!/bin/sh
# Create the USB gadget (NCM network + ACM serial) via configfs and bind it
# to the UDC. Runs once at boot from usb-gadget.service.
#
# Proven on msm8916 by the legacy KlipperPhonesLinux images: no built-in
# g_serial (it grabs the UDC before the OTG role is known — issue #36);
# instead userspace builds the gadget after the role settles. Gives:
#   - /dev/ttyGS0  (serial console; autottyGS0.service attaches login)
#   - usb0         (NCM network, phone is 192.168.100.1 — ssh over USB)
set -e

if [ -d /sys/class/udc ]; then
    UDC="$(ls /sys/class/udc | head -1)"
fi
[ -n "${UDC:-}" ] || { echo "no UDC found, skipping usb gadget setup"; exit 0; }

G=/sys/kernel/config/usb_gadget/g1
mkdir -p $G/configs/c.1
cd $G

mkdir -p strings/0x409
mkdir -p configs/c.1/strings/0x409

echo 0x0100 > idProduct
echo 0x18D1 > idVendor
echo 0xEF > bDeviceClass
echo 0x02 > bDeviceSubClass
echo 0x01 > bDeviceProtocol

echo "umeko" > strings/0x409/manufacturer
echo "NCM + Serial Gadget" > strings/0x409/product
echo "$(sha256sum < /etc/machine-id | cut -d' ' -f1)" > strings/0x409/serialnumber

echo "NCM + Serial" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

mkdir -p functions/ncm.usb0
echo "02:11:22:33:44:55" > functions/ncm.usb0/dev_addr
echo "02:11:22:33:44:56" > functions/ncm.usb0/host_addr
ln -s functions/ncm.usb0 configs/c.1

mkdir -p functions/acm.usb0
ln -s functions/acm.usb0 configs/c.1

echo "$UDC" > $G/UDC

ip link set usb0 up 2>/dev/null || true
ip addr add 192.168.100.1/24 dev usb0 2>/dev/null || true
