#!/bin/bash
# sudo modprobe gs_usb
sleep 15s
sudo ip link set can0 up type can bitrate 500000
sudo ifconfig can0 txqueuelen 1024
sleep 15s
# sudo ip link set can0 down
while true
do
	output=$(ifconfig | grep -o "can0")
	if [[ $output == *"can0"* ]]; then
    		echo "there is can0"
	else
    		echo "there is no can0"
		sudo ip link set can0 up type can bitrate 500000
		sudo ifconfig can0 txqueuelen 1024
	fi
	sleep 10s
done
