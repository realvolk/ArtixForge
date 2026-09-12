#!/usr/bin/env bash
set -Eeuo pipefail
[[ -f /etc/artix-installer.conf ]] && source /etc/artix-installer.conf || true

service_exists() {
    local svc="${1}" init="${INIT:-openrc}"
    case "${init}" in
        openrc) [[ -f "/etc/init.d/${svc}" ]] && return 0 ;;
        runit)  [[ -d "/etc/runit/sv/${svc}" ]] && return 0 ;;
        dinit)  [[ -f "/etc/dinit.d/${svc}" ]] && return 0 ;;
        s6)     [[ -d "/etc/s6/sv/${svc}" ]] && return 0 ;;
    esac
    return 1
}

enable_service() {
    local svc="${1}" init="${INIT:-openrc}"
    
    case "${init}:${svc}" in
        dinit:logind) svc="elogind" ;;
        dinit:dbus)   svc="dbus" ;;
    esac
    
    if ! service_exists "${svc}"; then
        warn_collect "Service '${svc}' not found for ${init} — enable manually after install"
        return 0
    fi
    case "${init}" in
        openrc) rc-update add "${svc}" default ;;
        runit)  mkdir -p /etc/runit/runsvdir/default ; ln -sf "/etc/runit/sv/${svc}" "/etc/runit/runsvdir/default/${svc}" ;;
        dinit)  mkdir -p /etc/dinit.d/boot.d ; ln -sf "../${svc}" "/etc/dinit.d/boot.d/${svc}" ;;
        s6)     s6-rc-bundle-update add default "${svc}" 2>/dev/null || true ;;
    esac
}

enable_service_boot() {
    local svc="${1}" init="${INIT:-openrc}"
    
    case "${init}:${svc}" in
        dinit:logind) svc="elogind" ;;
    esac
    
    if ! service_exists "${svc}"; then
        log_warn "Boot service '${svc}' not found for ${init} — skipping. It may need to be enabled manually after install."
        MISSING_SERVICES="${MISSING_SERVICES}  - ${svc} (${init}) [boot]\n"
        return 0
    fi
    case "${init}" in
        openrc) rc-update add "${svc}" boot ;;
        runit)  mkdir -p /etc/runit/runsvdir/boot ; ln -sf "/etc/runit/sv/${svc}" "/etc/runit/runsvdir/boot/${svc}" ;;
        dinit)  mkdir -p /etc/dinit.d/boot.d ; ln -sf "../${svc}" "/etc/dinit.d/boot.d/${svc}" ;;
        s6)     s6-rc-bundle-update add boot "${svc}" 2>/dev/null || true ;;
    esac
}

start_service() {
    local svc="${1}" init="${INIT:-openrc}"
    if ! service_exists "${svc}"; then
        log_warn "Cannot start '${svc}' — not found for ${init}."
        return 0
    fi
    case "${init}" in
        openrc) rc-service "${svc}" start || true ;;
        runit)  sv up "${svc}" || true ;;
        dinit)  dinitctl start "${svc}" || true ;;
        s6)     s6-rc -u change "${svc}" || true ;;
    esac
}