#!/usr/bin/env bash
set -Eeuo pipefail

stage_init() {
    if stage_should_skip init; then return 0; fi

    local init
    init="$(state_get INIT openrc)"

    [[ "${init}" == "busybox" ]] || {
        log_info "Skipping BusyBox init configuration (init: ${init})"
        stage_mark_done init
        return 0
    }

    log_info "Configuring BusyBox init..."

    cat > /mnt/etc/inittab <<'INITTAB'
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty 38400 tty1
::respawn:/sbin/getty 38400 tty2
::respawn:/sbin/getty 38400 tty3
::respawn:/sbin/getty 38400 tty4
::ctrlaltdel:/sbin/reboot
::shutdown:/etc/init.d/rcK
INITTAB

    cat > /mnt/etc/init.d/rcS <<'RCS'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run

mount -o remount,rw /

swapon -a 2>/dev/null || true

[[ -f /etc/hostname ]] && hostname -F /etc/hostname

if [[ -x /etc/init.d/network ]]; then
    /etc/init.d/network start
fi

for svc in /etc/init.d/*; do
    [[ -x "${svc}" ]] || continue
    [[ "$(basename "${svc}")" == "rcS" ]] && continue
    [[ "$(basename "${svc}")" == "rcK" ]] && continue
    "${svc}" start
done
RCS

    cat > /mnt/etc/init.d/rcK <<'RCK'
#!/bin/sh
for svc in $(ls -r /etc/init.d/*); do
    [[ -x "${svc}" ]] || continue
    [[ "$(basename "${svc}")" == "rcS" ]] && continue
    [[ "$(basename "${svc}")" == "rcK" ]] && continue
    "${svc}" stop 2>/dev/null || true
done

[[ -x /etc/init.d/network ]] && /etc/init.d/network stop 2>/dev/null || true

swapoff -a 2>/dev/null || true
umount -a -r 2>/dev/null || true
RCK

    chmod +x /mnt/etc/init.d/rcS /mnt/etc/init.d/rcK

    cat > /mnt/etc/init.d/network <<'NETWORK'
#!/bin/sh
case "$1" in
    start)
        if [[ -x /usr/bin/dhcpcd ]]; then
            dhcpcd -q
        elif [[ -x /usr/bin/NetworkManager ]]; then
            NetworkManager &
        fi
        ;;
    stop)
        pkill dhcpcd 2>/dev/null || true
        pkill NetworkManager 2>/dev/null || true
        ;;
esac
NETWORK
    chmod +x /mnt/etc/init.d/network

    if ! artix-chroot /mnt which busybox &>/dev/null; then
        log_warn "BusyBox not found in target. It should be built by Power User stage."
    fi

    log_info "BusyBox init configuration complete."
    stage_mark_done init
}