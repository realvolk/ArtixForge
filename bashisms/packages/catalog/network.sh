#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA NETWORK_PACKAGES
NETWORK_PACKAGES=(
    [networkmanager]="networkmanager networkmanager-@init@"
    [dhcpcd+iwd]="dhcpcd iwd dhcpcd-@init@ iwd-@init@"
    [connman]="connman connman-@init@"
    [none]=""
)

declare -gA NETWORK_SERVICES
NETWORK_SERVICES=(
    [networkmanager]="NetworkManager"
    [dhcpcd+iwd]="dhcpcd iwd"
    [connman]="connmand"
)

declare -ga NETWORK_LIST
NETWORK_LIST=(networkmanager dhcpcd+iwd connman none)