#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA SERVICE_MAP_OPENRC_DINIT
SERVICE_MAP_OPENRC_DINIT=(
    [NetworkManager]=NetworkManager
    [networkmanager]=NetworkManager
    [dhcpcd]=dhcpcd
    [iwd]=iwd
    [sshd]=sshd
    [cronie]=cronie
    [dbus]=dbus
    [elogind]=elogind
    [logind]=elogind
    [seatd]=seatd
    [acpid]=acpid
    [alsa]=alsa
    [bluetoothd]=bluetoothd
    [connmand]=connmand
    [ufw]=ufw
    [firewalld]=firewalld
    [ntpd]=ntpd
    [syslog-ng]=syslog-ng
    [lvm2-lvmetad]=lvm2
    [dmcrypt]=dmcrypt
    [zfs-zed]=zfs-zed
)

declare -gA SERVICE_MAP_OPENRC_RUNIT
SERVICE_MAP_OPENRC_RUNIT=(
    [NetworkManager]=NetworkManager
    [networkmanager]=NetworkManager
    [dhcpcd]=dhcpcd
    [iwd]=iwd
    [sshd]=sshd
    [cronie]=cronie
    [dbus]=dbus
    [elogind]=elogind
    [logind]=elogind
    [seatd]=seatd
    [acpid]=acpid
    [alsa]=alsa
    [bluetoothd]=bluetoothd
    [connmand]=connmand
    [ufw]=ufw
    [firewalld]=firewalld
    [ntpd]=ntpd
    [syslog-ng]=syslog-ng
)

declare -gA SERVICE_MAP_OPENRC_S6
SERVICE_MAP_OPENRC_S6=(
    [NetworkManager]=NetworkManager
    [networkmanager]=NetworkManager
    [dhcpcd]=dhcpcd
    [iwd]=iwd
    [sshd]=sshd
    [cronie]=cronie
    [dbus]=dbus
    [elogind]=elogind
    [logind]=elogind
    [seatd]=seatd
    [acpid]=acpid
    [alsa]=alsa
    [bluetoothd]=bluetoothd
    [connmand]=connmand
    [ufw]=ufw
    [firewalld]=firewalld
    [ntpd]=ntpd
    [syslog-ng]=syslog-ng
)

declare -gA SERVICE_MAP_SYSTEMD_OPENRC
SERVICE_MAP_SYSTEMD_OPENRC=(
    [NetworkManager]=NetworkManager
    [networkmanager]=NetworkManager
    [dhcpcd]=dhcpcd
    [iwd]=iwd
    [sshd]=sshd
    [cronie]=cronie
    [dbus]=dbus
    [elogind]=elogind
    [logind]=elogind
    [seatd]=seatd
    [acpid]=acpid
    [alsa-restore]=alsa
    [bluetooth]=bluetoothd
    [connman]=connmand
    [ufw]=ufw
    [firewalld]=firewalld
    [ntpd]=ntpd
    [syslog-ng]=syslog-ng
)

declare -gA SERVICE_MAP_DINIT_OPENRC
for _k in "${!SERVICE_MAP_OPENRC_DINIT[@]}"; do
    SERVICE_MAP_DINIT_OPENRC["${SERVICE_MAP_OPENRC_DINIT[$_k]}"]="$_k"
done
unset _k

declare -gA SERVICE_MAP_RUNIT_OPENRC
for _k in "${!SERVICE_MAP_OPENRC_RUNIT[@]}"; do
    SERVICE_MAP_RUNIT_OPENRC["${SERVICE_MAP_OPENRC_RUNIT[$_k]}"]="$_k"
done
unset _k

declare -gA SERVICE_MAP_S6_OPENRC
for _k in "${!SERVICE_MAP_OPENRC_S6[@]}"; do
    SERVICE_MAP_S6_OPENRC["${SERVICE_MAP_OPENRC_S6[$_k]}"]="$_k"
done
unset _k