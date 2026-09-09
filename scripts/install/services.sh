#!/usr/bin/env bash
set -Eeuo pipefail
[[ -f /etc/artix-installer.conf ]] && source /etc/artix-installer.conf || true

service_exists() {
    local svc="${1}" init="${INIT:-openrc}"
    case "${init}" in
        openrc) [[ -f "/etc/init.d/${svc}" ]] ;;
        runit)  [[ -d "/etc/runit/sv/${svc}" ]] ;;
        dinit)  [[ -f "/etc/dinit.d/${svc}" ]] ;;
        s6)     [[ -d "/etc/s6/sv/${svc}" ]] ;;
        *)      return 1 ;;
    esac
}

enable_service() {
    local svc="${1}" init="${INIT:-openrc}"
    
    case "${init}:${svc}" in
        dinit:logind) svc="elogind" ;;
        dinit:dbus)   svc="dbus" ;;
    esac
    
    if ! service_exists "${svc}"; then
        warn_collect "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc) rc-update add "${svc}" default ;;
        runit)  mkdir -p /etc/runit/runsvdir/default ; ln -sf "/etc/runit/sv/${svc}" "/etc/runit/runsvdir/default/${svc}" ;;
        dinit)  mkdir -p /etc/dinit.d/boot.d ; ln -sf "../${svc}" "/etc/dinit.d/boot.d/${svc}" ;;
        s6)     s6-rc-bundle-update add default "${svc}" 2>/dev/null || warn_collect "Failed to enable ${svc} for s6" ;;
    esac
}

enable_service_boot() {
    local svc="${1}" init="${INIT:-openrc}"
    
    case "${init}:${svc}" in
        dinit:logind) svc="elogind" ;;
    esac
    
    if ! service_exists "${svc}"; then
        warn_collect "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc) rc-update add "${svc}" boot ;;
        runit)  mkdir -p /etc/runit/runsvdir/boot ; ln -sf "/etc/runit/sv/${svc}" "/etc/runit/runsvdir/boot/${svc}" ;;
        dinit)  mkdir -p /etc/dinit.d/boot.d ; ln -sf "../${svc}" "/etc/dinit.d/boot.d/${svc}" ;;
        s6)     s6-rc-bundle-update add boot "${svc}" 2>/dev/null || warn_collect "Failed to enable ${svc} for s6 boot" ;;
    esac
}

start_service() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        warn_collect "Service not found for ${init}: ${svc}"
        return 1
    fi
    case "${init}" in
        openrc) rc-service "${svc}" start || true ;;
        runit)  sv up "${svc}" || true ;;
        dinit)  dinitctl start "${svc}" || true ;;
        s6)     s6-rc -u change "${svc}" || true ;;
    esac
}