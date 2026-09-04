#!/bin/bash


sleep 10
rmmod rmi_i2c
rmmod atmel_mxt_ts
sleep 1
modprobe rmi_i2c
sleep 1
modprobe atmel_mxt_ts
