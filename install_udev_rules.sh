#!/bin/bash

UDEV_RULES_DIR=/etc/udev/rules.d
MY_RULES_DIR=`pwd`/udev-rules
BIN_DIR=/usr/bin/

check_root() {
    if [ $UID != 0 ]; then
        echo "The script must be executed as root"
        exit 1
    fi
}

copy_rules() {
    cp $MY_RULES_DIR/* $UDEV_RULES_DIR

    if [ "z$?" != "z0" ]; then
        echo "Failed to install udev rules."
        exit 1
    fi

    udevadm control -R

    if [ "z$?" != "z0" ]; then
        echo "Failed to reload udev rules."
        exit 1
    fi

    printf "Rules were installed:\n`ls $MY_RULES_DIR`\n"
}

copy_scripts() {
    cp devicekit*.sh $BIN_DIR

    if [ "z$?" != "z0" ]; then
        echo "Failed to install devicekit scripts."
        exit 1
    fi

    printf "Scripts were copied:\n`ls devicekit*.sh`\n"
}

check_root
copy_rules
copy_scripts
