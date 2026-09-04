#!/bin/bash

while true; do
    # Check if /dev/ttyGS0 exists
    if [ ! -c "/dev/ttyGS0" ]; then
        echo "/dev/ttyGS0 does not exist."
        sleep 15
        continue
    fi
    # echo "/dev/ttyGS0 exist and trying start console."
    break
    # Run the agetty command
    # agetty -L ttyGS0 115200 vt100

    # If agetty exits, wait for one second and restart the loop
    # sleep 10
done
# agetty -L -i ttyGS0 115200 vt100
echo "welcome to Umeko KlipperLinux console !"
login -f umeko < /dev/ttyGS0
