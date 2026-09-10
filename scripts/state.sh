#!/usr/bin/env bash
set -Eeuo pipefail

readonly STATE_ROOT="/tmp/artix-installer"
readonly STATE_FILE="${STATE_ROOT}/state.conf"
readonly STAGE_DIR="${STATE_ROOT}/stages"
readonly LOG_DIR="${STATE_ROOT}/logs"

ensure_state_dirs() {
    mkdir -p "${STATE_ROOT}" "${STAGE_DIR}" "${LOG_DIR}"
}

lint_state() {
    local errors=""

    local -a required_keys=(DISK FS_TYPE BOOTLOADER KERNEL_CHOICE INIT)
    for key in "${required_keys[@]}"; do
        local val
        val=$(state_get "$key" "")
        [[ -n "$val" ]] || errors+="Missing required key: ${key}"$'\n'
    done

    local disk
    disk=$(state_get DISK "")
    if [[ -n "$disk" && ! -b "$disk" ]]; then
        errors+="DISK '${disk}' is not a valid block device"$'\n'
    fi

    local fs
    fs=$(state_get FS_TYPE "")
    if [[ -n "$fs" ]]; then
        case "$fs" in
            ext4|btrfs|xfs|f2fs) ;;
            *) errors+="FS_TYPE '${fs}' is not supported"$'\n' ;;
        esac
    fi

    local init
    init=$(state_get INIT "")
    if [[ -n "$init" ]]; then
        case "$init" in
            openrc|runit|dinit|s6|busybox) ;;
            *) errors+="INIT '${init}' is not supported"$'\n' ;;
        esac
    fi

    local bootloader
    bootloader=$(state_get BOOTLOADER "")
    if [[ -n "$bootloader" ]]; then
        case "$bootloader" in
            grub|refind|efistub|limine) ;;
            *) errors+="BOOTLOADER '${bootloader}' is not supported"$'\n' ;;
        esac
    fi

    local priv_esc
    priv_esc=$(state_get PRIV_ESCALATION "")
    if [[ -n "$priv_esc" ]]; then
        case "$priv_esc" in
            sudo|doas) ;;
            *) errors+="PRIV_ESCALATION '${priv_esc}' is not supported"$'\n' ;;
        esac
    fi

    local x_stack
    x_stack=$(state_get X_STACK "")
    if [[ -n "$x_stack" ]]; then
        case "$x_stack" in
            xorg|wayland|none) ;;
            *) errors+="X_STACK '${x_stack}' is not supported"$'\n' ;;
        esac
    fi

    local user_count
    user_count=$(state_get USER_COUNT 0)
    if [[ "$user_count" -eq 0 ]]; then
        local root_pass
        root_pass=$(state_get ROOT_PASS "")
        [[ -n "$root_pass" ]] || errors+="No users and no root password configured"$'\n'
    fi

    if [[ -n "$errors" ]]; then
        echo "$errors"
        return 1
    fi

    return 0
}

state_load_preset() {
    local preset_file="${1}"
    [[ -f "${preset_file}" ]] || return 1

    local base_state
    base_state=$(grep '^BASE_STATE=' "${preset_file}" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d "'\"")

    if [[ -n "${base_state}" ]]; then
        if [[ "${base_state}" != /* ]]; then
            base_state="$(dirname "${preset_file}")/${base_state}"
        fi
        if [[ ! -f "${base_state}" ]]; then
            log_warn "BASE_STATE not found: ${base_state}"
        else
            while IFS='=' read -r key value; do
                [[ -z "${key}" || "${key}" == \#* || "${key}" == "BASE_STATE" ]] && continue
                value="${value#\'}"; value="${value%\'}"
                value="${value#\"}"; value="${value%\"}"
                [[ -n "${value}" ]] && state_set "${key}" "${value}"
            done < "${base_state}"
        fi
    fi

    while IFS='=' read -r key value; do
        [[ -z "${key}" || "${key}" == \#* || "${key}" == "BASE_STATE" ]] && continue
        value="${value#\'}"; value="${value%\'}"
        value="${value#\"}"; value="${value%\"}"
        [[ -n "${value}" ]] && state_set "${key}" "${value}"
    done < "${preset_file}"

    state_resolve_templates
}

state_resolve_templates() {
    local -A values
    local key value ref resolved pass

    while IFS='=' read -r key value; do
        [[ -z "${key}" || "${key}" == \#* ]] && continue
        value="${value#\'}"; value="${value%\'}"
        value="${value#\"}"; value="${value%\"}"
        values["${key}"]="${value}"
    done < "${STATE_FILE}"

    local changed=1
    local iterations=0
    while [[ ${changed} -eq 1 && ${iterations} -lt 10 ]]; do
        changed=0
        iterations=$((iterations + 1))

        for key in "${!values[@]}"; do
            value="${values[${key}]}"
            if [[ "${value}" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; then
                ref="${BASH_REMATCH[1]}"
                resolved="${values[${ref}]:-}"
                if [[ -n "${resolved}" ]]; then
                    values["${key}"]="${value//\$\{${ref}\}/${resolved}}"
                    changed=1
                fi
            fi
        done
    done

    for key in "${!values[@]}"; do
        state_set "${key}" "${values[${key}]}"
    done
}

state_encrypt_preset() {
    local preset="${1}"
    [[ -f "${preset}" ]] || { log_error "Preset not found: ${preset}"; return 1; }

    local passphrase confirm
    passphrase=$(tui_password "Preset Encryption" "Enter passphrase to encrypt this preset:") || return 1
    confirm=$(tui_password "Preset Encryption" "Confirm passphrase:") || return 1
    [[ "${passphrase}" == "${confirm}" ]] || { tui_msg_quick "Mismatch" "Passphrases do not match."; return 1; }

    local temp_encrypted
    temp_encrypted=$(mktemp)

    {
        printf 'ARTIXFORGE_ENCRYPTED=1\n'
        gpg --symmetric --cipher-algo AES256 --batch --yes \
            --passphrase-fd 3 3<<<"${passphrase}" \
            --output - "${preset}" 2>/dev/null | base64
    } > "${temp_encrypted}"

    mv "${temp_encrypted}" "${preset}.enc"
    chmod 600 "${preset}.enc"
    rm -f "${preset}"
    log_info "Encrypted preset saved to ${preset}.enc"
}

state_decrypt_preset() {
    local encrypted="${1}"
    [[ -f "${encrypted}" ]] || { log_error "Encrypted preset not found: ${encrypted}"; return 1; }

    head -n1 "${encrypted}" | grep -q 'ARTIXFORGE_ENCRYPTED=1' || {
        log_error "Not an encrypted ArtixForge preset"
        return 1
    }

    local passphrase
    passphrase=$(tui_password "Preset Decryption" "Enter passphrase to decrypt this preset:") || return 1

    local temp_base64 temp_decrypted
    temp_base64=$(mktemp)
    temp_decrypted=$(mktemp)

    tail -n +2 "${encrypted}" | base64 -d > "${temp_base64}" 2>/dev/null
    gpg --decrypt --batch --yes --passphrase-fd 3 3<<<"${passphrase}" \
        --output "${temp_decrypted}" "${temp_base64}" 2>/dev/null || {
        tui_msg_quick "Decryption Failed" "Wrong passphrase or corrupted file."
        rm -f "${temp_base64}" "${temp_decrypted}"
        return 1
    }

    cat "${temp_decrypted}"
    rm -f "${temp_base64}" "${temp_decrypted}"
}

state_save() {
    ensure_state_dirs
    local tmp_state="${STATE_FILE}.tmp"
    local user_json user_count
    user_json=$(state_get USER_COUNT '')
    user_count=0
    if [[ -n "${user_json}" && "${user_json}" != "0" && "${user_json}" != "[]" ]]; then
        user_count=$(echo "${user_json}" | jq '. | length' 2>/dev/null || echo 0)
    fi
    {
        printf "MODE='%s'\n"                  "$(state_get MODE auto)"
        printf "DISK='%s'\n"                  "$(state_get DISK '')"
        printf "FS_TYPE='%s'\n"               "$(state_get FS_TYPE ext4)"
        printf "INIT='%s'\n"                  "$(state_get INIT openrc)"
        printf "USE_LUKS='%s'\n"              "$(state_get USE_LUKS no)"
        printf "LUKS_PASS='%s'\n"             "$(state_get LUKS_PASS '')"
        printf "BOOTLOADER='%s'\n"            "$(state_get BOOTLOADER grub)"
        printf "DISPLAY_MANAGER='%s'\n"       "$(state_get DISPLAY_MANAGER none)"
        printf "AUDIO_STACK='%s'\n"           "$(state_get AUDIO_STACK pipewire)"
        printf "SWAP_ENABLED='%s'\n"          "$(state_get SWAP_ENABLED none)"
        printf "SWAP_SIZE='%s'\n"             "$(state_get SWAP_SIZE 0)"
        printf "ZRAM_PERCENT='%s'\n"          "$(state_get ZRAM_PERCENT 50)"
        printf "EXTRAS='%s'\n"                "$(state_get EXTRAS '')"
        printf "KERNEL_CHOICE='%s'\n"         "$(state_get KERNEL_CHOICE linux)"
        printf "KERNEL_IMAGE='%s'\n"          "$(state_get KERNEL_IMAGE '')"
        printf "INITRAMFS_IMAGE='%s'\n"       "$(state_get INITRAMFS_IMAGE '')"
        printf "MICROCODE_IMAGE='%s'\n"       "$(state_get MICROCODE_IMAGE '')"
        printf "MICROCODE_OVERRIDE='%s'\n"    "$(state_get MICROCODE_OVERRIDE auto)"
        printf "HOSTNAME='%s'\n"              "$(state_get HOSTNAME artix)"
        printf "TIMEZONE='%s'\n"              "$(state_get TIMEZONE Europe/Belgrade)"
        printf "LOCALE='%s'\n"                "$(state_get LOCALE en_US.UTF-8)"
        printf "KEYMAP='%s'\n"                "$(state_get KEYMAP us)"
        printf "BTRFS_LAYOUT='%s'\n"          "$(state_get BTRFS_LAYOUT standard)"
        printf "WM_DE='%s'\n"                 "$(state_get WM_DE none)"
        printf "KDE_PROFILE='%s'\n"           "$(state_get KDE_PROFILE desktop)"
        printf "ROOT_PASS='%s'\n"             "$(state_get ROOT_PASS '')"
        printf "USER_COUNT='%s'\n"            "$(state_get USER_COUNT 1)"
        for ((i=1; i<=user_count; i++)); do
            printf "USER_%d_NAME='%s'\n"   "$i" "$(state_get "USER_${i}_NAME" "")"
            printf "USER_%d_PASS='%s'\n"   "$i" "$(state_get "USER_${i}_PASS" "")"
            printf "USER_%d_SHELL='%s'\n"  "$i" "$(state_get "USER_${i}_SHELL" "/bin/bash")"
            printf "USER_%d_GROUPS='%s'\n" "$i" "$(state_get "USER_${i}_GROUPS" "wheel,audio,video,storage")"
            printf "USER_%d_SUDO='%s'\n"   "$i" "$(state_get "USER_${i}_SUDO" "yes")"
            printf "USER_%d_DE='%s'\n"     "$i" "$(state_get "USER_${i}_DE" "")"
            printf "USER_%d_DOTFILES='%s'\n" "$i" "$(state_get "USER_${i}_DOTFILES" "")"
        done
        printf "USER_SHELL='%s'\n"            "$(state_get USER_SHELL /bin/bash)"
        printf "PRIV_ESCALATION='%s'\n"       "$(state_get PRIV_ESCALATION sudo)"
        printf "NETWORK_STACK='%s'\n"         "$(state_get NETWORK_STACK dhcpcd+iwd)"
        printf "ALLOW_OFFLINE='%s'\n"         "$(state_get ALLOW_OFFLINE no)"
        printf "X_STACK='%s'\n"               "$(state_get X_STACK xorg)"
        printf "ENABLE_ARCH_REPOS='%s'\n"     "$(state_get ENABLE_ARCH_REPOS no)"
        printf "GENERATE_UKI='%s'\n"          "$(state_get GENERATE_UKI no)"
        printf "USE_LVM='%s'\n"               "$(state_get USE_LVM no)"
        printf "KEEP_BINARY_KERNEL='%s'\n"    "$(state_get KEEP_BINARY_KERNEL yes)"
        printf "COREUTILS='%s'\n"             "$(state_get COREUTILS gnu)"
        printf "KERNEL_CONFIG_DEPTH='%s'\n"   "$(state_get KERNEL_CONFIG_DEPTH auto)"
        printf "QUICK_INSTALL='%s'\n"         "$(state_get QUICK_INSTALL no)"
        printf "POWER_USER='%s'\n"            "$(state_get POWER_USER no)"
        printf "POWERUSER_PACKAGES='%s'\n"    "$(state_get POWERUSER_PACKAGES '')"
        printf "POWERUSER_PROFILE='%s'\n"     "$(state_get POWERUSER_PROFILE default)"
        printf "ENABLE_AURIS='%s'\n"          "$(state_get ENABLE_AURIS no)"
        printf "LUKS_KEYFILE='%s'\n"          "$(state_get LUKS_KEYFILE no)"
        printf "LUKS_KEYFILE_PATH='%s'\n"     "$(state_get LUKS_KEYFILE_PATH '')"
        printf "ISO_ARCH_REPOS='%s'\n"        "$(state_get ISO_ARCH_REPOS no)"
        printf "ARTIX_BOOT_MODE='%s'\n"       "$(state_get ARTIX_BOOT_MODE uefi)"
        printf "TKG_SCHEDULER='%s'\n"         "$(state_get TKG_SCHEDULER eevdf)"
        printf "TKG_BINARY='%s'\n"            "$(state_get TKG_BINARY no)"
        printf "TKG_COMPILER='%s'\n"          "$(state_get TKG_COMPILER gcc)"
        printf "TKG_OPTLEVEL='%s'\n"          "$(state_get TKG_OPTLEVEL 1)"
        printf "TKG_PROCESSOR_OPT='%s'\n"     "$(state_get TKG_PROCESSOR_OPT native)"
        printf "TKG_LTO_MODE='%s'\n"          "$(state_get TKG_LTO_MODE no)"
        printf "TKG_PREEMPT_RT='%s'\n"        "$(state_get TKG_PREEMPT_RT 0)"
        printf "TKG_TICKLESS='%s'\n"          "$(state_get TKG_TICKLESS 2)"
        printf "TKG_TIMER_FREQ='%s'\n"        "$(state_get TKG_TIMER_FREQ 1000)"
        printf "TKG_CPU_GOV='%s'\n"           "$(state_get TKG_CPU_GOV ondemand)"
        printf "TKG_GLITCHED_BASE='%s'\n"     "$(state_get TKG_GLITCHED_BASE false)"
        printf "TKG_ZENIFY='%s'\n"            "$(state_get TKG_ZENIFY false)"
        printf "TKG_CLEAR_PATCHES='%s'\n"     "$(state_get TKG_CLEAR_PATCHES false)"
        printf "TKG_OPENRGB='%s'\n"           "$(state_get TKG_OPENRGB false)"
        printf "TKG_ACS_OVERRIDE='%s'\n"      "$(state_get TKG_ACS_OVERRIDE false)"
        printf "TKG_FSYNC='%s'\n"             "$(state_get TKG_FSYNC false)"
        printf "TKG_MGLRU='%s'\n"             "$(state_get TKG_MGLRU false)"
        printf "TKG_NTSYNC='%s'\n"            "$(state_get TKG_NTSYNC false)"
        printf "TKG_NR_CPUS='%s'\n"           "$(state_get TKG_NR_CPUS "$(nproc)")"
        printf "KERNEL_ADV_FS='%s'\n"         "$(state_get KERNEL_ADV_FS ext4)"
        printf "KERNEL_ADV_GPU='%s'\n"        "$(state_get KERNEL_ADV_GPU '')"
        printf "KERNEL_ADV_NET='%s'\n"        "$(state_get KERNEL_ADV_NET '')"
        printf "KERNEL_ADV_SOUND='%s'\n"      "$(state_get KERNEL_ADV_SOUND '')"
        printf "KERNEL_ADV_USB='%s'\n"        "$(state_get KERNEL_ADV_USB '')"
        printf "KERNEL_ADV_SECURITY='%s'\n"   "$(state_get KERNEL_ADV_SECURITY '')"
        printf "KERNEL_ADV_VIRT='%s'\n"       "$(state_get KERNEL_ADV_VIRT '')"
        printf "KERNEL_ADV_DEBUG='%s'\n"      "$(state_get KERNEL_ADV_DEBUG '')"
        printf "KERNEL_PREEMPT='%s'\n"        "$(state_get KERNEL_PREEMPT voluntary)"
        printf "KERNEL_TIMER='%s'\n"          "$(state_get KERNEL_TIMER 250)"
        printf "KERNEL_GOVERNOR='%s'\n"       "$(state_get KERNEL_GOVERNOR schedutil)"
        printf "TARGET_ARCH='%s'\n"           "$(state_get TARGET_ARCH '')"
        printf "BOARD_NAME='%s'\n"            "$(state_get BOARD_NAME '')"
        printf "UBOOT_TARGET='%s'\n"          "$(state_get UBOOT_TARGET '')"
        printf "MIGRATION_TYPE='%s'\n"        "$(state_get MIGRATION_TYPE '')"
        printf "MIGRATION_SRC='%s'\n"         "$(state_get MIGRATION_SRC '')"
        printf "MIGRATION_TGT='%s'\n"         "$(state_get MIGRATION_TGT '')"
        printf "MIG_ROOT='%s'\n"              "$(state_get MIG_ROOT '')"
        printf "DE_MIG_DM='%s'\n"             "$(state_get DE_MIG_DM '')"
        printf "DE_MIG_X='%s'\n"              "$(state_get DE_MIG_X '')"
        printf "DE_MIG_AUDIO='%s'\n"          "$(state_get DE_MIG_AUDIO '')"
        printf "DE_MIG_NETWORK='%s'\n"        "$(state_get DE_MIG_NETWORK '')"
        printf "DE_MIG_EXTRAS='%s'\n"         "$(state_get DE_MIG_EXTRAS '')"
        printf "ATA_AUR_HELPER='%s'\n"        "$(state_get ATA_AUR_HELPER '')"
        printf "ATA_HAS_HOMED='%s'\n"         "$(state_get ATA_HAS_HOMED 0)"
        printf "POST_INSTALL_SCRIPT='%s'\n"   "$(state_get POST_INSTALL_SCRIPT '')"
        printf "POST_INSTALL_ONESHOT='%s'\n"  "$(state_get POST_INSTALL_ONESHOT '')"
    } > "${tmp_state}"
    mv "${tmp_state}" "${STATE_FILE}"
    chmod 600 "${STATE_FILE}"
}

state_load() {
    [[ -f "${STATE_FILE}" ]] || return 0
    source "${STATE_FILE}"
}

state_get() {
    local key="${1}"
    local default="${2:-}"
    if [[ -f "${STATE_FILE}" ]]; then
        local value
        value=$(grep "^${key}=" "${STATE_FILE}" 2>/dev/null || true | tail -1 | sed "s|^${key}=||")
        if [[ -n "${value}" ]]; then
            while true; do
                local changed=0
                if [[ "${value}" == \'*\' ]]; then
                    value="${value#\'}"
                    value="${value%\'}"
                    changed=1
                fi
                if [[ "${value}" == ${key}=* ]]; then
                    value="${value#${key}=}"
                    changed=1
                fi
                [[ $changed -eq 0 ]] && break
            done
            printf '%s\n' "${value}"
            return 0
        fi
    fi
    printf '%s\n' "${!key:-${default}}"
}

state_set() {
    ensure_state_dirs
    local key="${1}" value="${2}"
    [[ -n "${key}" ]] || { log_error "state_set: empty key"; return 1; }
    export "${key}=${value}"

    if [[ -f "${STATE_FILE}" ]] && grep -q "^${key}=" "${STATE_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}='${value}'|" "${STATE_FILE}"
    else
        printf "%s='%s'\n" "${key}" "${value}" >> "${STATE_FILE}"
    fi
}

stage_mark_done() {
    ensure_state_dirs;

    touch "${STAGE_DIR}/${1}.done";
}

stage_is_done() {
    [[ -f "${STAGE_DIR}/${1}.done" ]];
}

stage_reset() {
    rm -f "${STAGE_DIR}/${1}.done";
}

stage_reset_all() {
    rm -f "${STAGE_DIR}"/*.done;
}

stage_log_path() {
    ensure_state_dirs;

    printf '%s/%s.log\n' \
        "${LOG_DIR}" \
        "${1}";
}

stage_require_mount() {
    mountpoint -q /mnt
}

stage_require_storage() {
    stage_require_mount \
        && [[ -d /mnt/etc ]] \
        && (
            mountpoint -q /mnt/boot \
            || mountpoint -q /mnt/efi \
            || mountpoint -q /mnt/boot/efi \
            || [[ -f /mnt/etc/fstab ]]
        )
}

stage_require_chroot() {
    stage_require_storage \
        && [[ -x /mnt/usr/bin/bash ]] \
        && [[ -f /mnt/etc/fstab ]]
}

stage_require_post() {
    stage_require_chroot \
        && [[ -d /mnt/home || -d /mnt/root ]]
}

stage_validate() {
    local stage="${1}";

    case "${stage}" in
        preflight)  return 0 ;;
        storage)    [[ -b "$(state_get DISK)" ]] ;;
        base)       [[ -x /mnt/usr/bin/bash ]] && artix-chroot /mnt pacman -Q base &>/dev/null ;;
        poweruser)  [[ -f /mnt/etc/artix-poweruser/world.txt ]] && [[ -f /mnt/boot/vmlinuz-linux-custom ]] ;;
        chroot)     [[ -f /mnt/etc/fstab ]] && [[ -f /mnt/etc/hostname ]] ;;
        init)       return 0 ;;
        post)       [[ -d /mnt/home || -d /mnt/root ]] ;;
        finalize)   return 0 ;;
        *)          return 1 ;;
    esac
}

stage_reset_from() {
    local stage="${1}";
    local reset='false';
    local current;

    for current in \
        preflight \
        storage \
        base \
        poweruser \
        chroot \
        init \
        post \
        finalize; do

        if [[ "${current}" == "${stage}" ]]; then
            reset='true';
        fi

        if [[ "${reset}" == 'true' ]]; then
            stage_reset "${current}";
        fi
    done
}

stage_should_skip() {
    local stage="${1}";

    if ! stage_is_done "${stage}"; then
        return 1;
    fi

    if ! stage_validate "${stage}"; then
        printf '[!] Stage "%s" marked complete but environment is invalid.\n' \
            "${stage}";

        printf '[!] Resetting stage state...\n';

        stage_reset_from "${stage}";

        return 1;
    fi

    printf '[*] %s stage already completed. Skipping...\n' \
        "${stage^}";

    return 0;
}