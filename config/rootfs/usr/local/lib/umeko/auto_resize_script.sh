#!/bin/bash

resize2fs $(df / | awk '$NF=="/"{print $1}')
# resize2fs /dev/mmcblk0p30
# resize2fs /dev/mmcblk1p30
