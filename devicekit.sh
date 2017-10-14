#!/bin/bash

set -x

USERNAME=$1
METHOD=$2
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/`id -u $USERNAME`/bus"
DBUS_OBJECT_PATH="/"
DBUS_INTERFACE="redflat.devicekit"

dbus-send --session $DBUS_OBJECT_PATH ${DBUS_INTERFACE}.${METHOD} ${@:3}
