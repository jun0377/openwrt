#!/bin/bash

function get_usb_by_ttyUSB()
{
    # /dev/ttyUSB2 => ttyUSB2
    local ttyUSB=$(basename $1)
    local USB=$(find /sys/devices/platform -name ${ttyUSB} | head -n 1 | awk -F'/' '{print $(NF-1)}')
    echo ${USB}
}

function get_simindex_by_usb()
{
    local USB=$1
    [ "${USB}" == "2-1:1.4" ] && echo "SIM_5G_1" && return
    [ "${USB}" == "2-2:1.4" ] && echo "SIM_5G_1" && return
    [ "${USB}" == "2-3:1.4" ] && echo "SIM_5G_1" && return
}

usb=$(get_usb_by_ttyUSB /dev/ttyUSB2)
echo ${usb}
index=$(get_simindex_by_usb ${usb})
echo ${index}
