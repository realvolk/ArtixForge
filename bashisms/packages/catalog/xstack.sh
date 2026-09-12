#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA X_STACK_PACKAGES
X_STACK_PACKAGES=(
    [xorg]="xorg-server xorg-xinit xorg-xset xorg-xrandr xf86-input-libinput xf86-input-evdev"
    [xorg-tearfree]="xorg-server-tearfree xorg-xinit xorg-xset xorg-xrandr xf86-input-libinput xf86-input-evdev"
    [wayland]=""
    [none]=""
)