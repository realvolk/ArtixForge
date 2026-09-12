#!/usr/bin/env bash
set -Eeuo pipefail

readonly STATE_ROOT="/tmp/artix-installer"
readonly STATE_FILE="${STATE_ROOT}/state.conf"
readonly STAGE_DIR="${STATE_ROOT}/stages"
readonly LOG_DIR="${STATE_ROOT}/logs"

declare -ga STATE_KEYS
STATE_KEYS=(
    MODE DISK FS_TYPE INIT USE_LUKS LUKS_PASS LUKS_KEYFILE LUKS_KEYFILE_PATH
    BOOTLOADER DISPLAY_MANAGER AUDIO_STACK SWAP_ENABLED SWAP_SIZE ZRAM_PERCENT
    EXTRAS KERNEL_CHOICE KERNEL_IMAGE INITRAMFS_IMAGE MICROCODE_IMAGE
    MICROCODE_OVERRIDE HOSTNAME TIMEZONE LOCALE KEYMAP BTRFS_LAYOUT WM_DE
    KDE_PROFILE ROOT_PASS USER_COUNT USER_SHELL PRIV_ESCALATION NETWORK_STACK
    ALLOW_OFFLINE X_STACK ENABLE_ARCH_REPOS GENERATE_UKI USE_LVM LVM_VG_NAME
    KEEP_BINARY_KERNEL COREUTILS KERNEL_CONFIG_DEPTH QUICK_PROFILE
    PROFILE_PACKAGES QUICK_INSTALL POWER_USER POWERUSER_PACKAGES
    POWERUSER_PROFILE ENABLE_AURIS ISO_ARCH_REPOS ISO_BASE_PROFILE
    ISO_BOOT_MODE ISO_OUTPUT_DIR ISO_EXTRA_PACKAGES ARTIX_BOOT_MODE
    TKG_SCHEDULER TKG_BINARY TKG_COMPILER TKG_OPTLEVEL TKG_PROCESSOR_OPT
    TKG_LTO_MODE TKG_PREEMPT_RT TKG_TICKLESS TKG_TIMER_FREQ TKG_CPU_GOV
    TKG_GLITCHED_BASE TKG_ZENIFY TKG_CLEAR_PATCHES TKG_OPENRGB
    TKG_ACS_OVERRIDE TKG_FSYNC TKG_MGLRU TKG_NTSYNC TKG_NR_CPUS
    KERNEL_ADV_FS KERNEL_ADV_GPU KERNEL_ADV_NET KERNEL_ADV_SOUND
    KERNEL_ADV_USB KERNEL_ADV_SECURITY KERNEL_ADV_VIRT KERNEL_ADV_DEBUG
    KERNEL_PREEMPT KERNEL_TIMER KERNEL_GOVERNOR TARGET_ARCH BOARD_NAME
    UBOOT_TARGET MIGRATION_TYPE MIGRATION_SRC MIGRATION_TGT MIG_ROOT
    DE_MIG_DM DE_MIG_X DE_MIG_AUDIO DE_MIG_NETWORK DE_MIG_EXTRAS
    ATA_AUR_HELPER ATA_HAS_HOMED POST_INSTALL_SCRIPT POST_INSTALL_ONESHOT
    RECOVERY_STATUS FSTAB_ISSUES BOOT_ISSUES PACMAN_ISSUES MIGRATION_ISSUES
    ISO_ISSUES BROKEN_PACKAGES SEAT_MANAGER SEAT_MANAGER_DISABLED HAS_CHAOTIC
    GPU_DRIVER VM_GUEST DISPLAY_PROTOCOL CPU_UCODE GUM_TITLE_COLOR
    GUM_ACCENT_COLOR
)

declare -gA STATE_DEFAULTS
STATE_DEFAULTS=(
    [MODE]=auto
    [DISK]=""
    [FS_TYPE]=ext4
    [INIT]=openrc
    [USE_LUKS]=no
    [LUKS_PASS]=""
    [LUKS_KEYFILE]=no
    [LUKS_KEYFILE_PATH]=""
    [BOOTLOADER]=grub
    [DISPLAY_MANAGER]=none
    [AUDIO_STACK]=pipewire
    [SWAP_ENABLED]=none
    [SWAP_SIZE]=0
    [ZRAM_PERCENT]=50
    [EXTRAS]=""
    [KERNEL_CHOICE]=linux
    [KERNEL_IMAGE]=""
    [INITRAMFS_IMAGE]=""
    [MICROCODE_IMAGE]=""
    [MICROCODE_OVERRIDE]=auto
    [HOSTNAME]=artix
    [TIMEZONE]=Europe/Belgrade
    [LOCALE]=en_US.UTF-8
    [KEYMAP]=us
    [BTRFS_LAYOUT]=standard
    [WM_DE]=none
    [KDE_PROFILE]=desktop
    [ROOT_PASS]=""
    [USER_COUNT]=1
    [USER_SHELL]=/bin/bash
    [PRIV_ESCALATION]=sudo
    [NETWORK_STACK]=dhcpcd+iwd
    [ALLOW_OFFLINE]=no
    [X_STACK]=xorg
    [ENABLE_ARCH_REPOS]=no
    [GENERATE_UKI]=no
    [USE_LVM]=no
    [LVM_VG_NAME]=vg0
    [KEEP_BINARY_KERNEL]=yes
    [COREUTILS]=gnu
    [KERNEL_CONFIG_DEPTH]=auto
    [QUICK_PROFILE]=""
    [PROFILE_PACKAGES]=""
    [QUICK_INSTALL]=no
    [POWER_USER]=no
    [POWERUSER_PACKAGES]=""
    [POWERUSER_PROFILE]=default
    [ENABLE_AURIS]=no
    [ISO_ARCH_REPOS]=no
    [ISO_BASE_PROFILE]=base
    [ISO_BOOT_MODE]=live
    [ISO_OUTPUT_DIR]=""
    [ISO_EXTRA_PACKAGES]=""
    [ARTIX_BOOT_MODE]=uefi
    [TKG_SCHEDULER]=eevdf
    [TKG_BINARY]=no
    [TKG_COMPILER]=gcc
    [TKG_OPTLEVEL]=1
    [TKG_PROCESSOR_OPT]=native
    [TKG_LTO_MODE]=no
    [TKG_PREEMPT_RT]=0
    [TKG_TICKLESS]=2
    [TKG_TIMER_FREQ]=1000
    [TKG_CPU_GOV]=ondemand
    [TKG_GLITCHED_BASE]=false
    [TKG_ZENIFY]=false
    [TKG_CLEAR_PATCHES]=false
    [TKG_OPENRGB]=false
    [TKG_ACS_OVERRIDE]=false
    [TKG_FSYNC]=false
    [TKG_MGLRU]=false
    [TKG_NTSYNC]=false
    [TKG_NR_CPUS]=""
    [KERNEL_ADV_FS]=ext4
    [KERNEL_ADV_GPU]=""
    [KERNEL_ADV_NET]=""
    [KERNEL_ADV_SOUND]=""
    [KERNEL_ADV_USB]=""
    [KERNEL_ADV_SECURITY]=""
    [KERNEL_ADV_VIRT]=""
    [KERNEL_ADV_DEBUG]=""
    [KERNEL_PREEMPT]=voluntary
    [KERNEL_TIMER]=250
    [KERNEL_GOVERNOR]=schedutil
    [TARGET_ARCH]=""
    [BOARD_NAME]=""
    [UBOOT_TARGET]=""
    [MIGRATION_TYPE]=""
    [MIGRATION_SRC]=""
    [MIGRATION_TGT]=""
    [MIG_ROOT]=""
    [DE_MIG_DM]=""
    [DE_MIG_X]=""
    [DE_MIG_AUDIO]=""
    [DE_MIG_NETWORK]=""
    [DE_MIG_EXTRAS]=""
    [ATA_AUR_HELPER]=""
    [ATA_HAS_HOMED]=0
    [POST_INSTALL_SCRIPT]=""
    [POST_INSTALL_ONESHOT]=""
    [RECOVERY_STATUS]=""
    [FSTAB_ISSUES]=none
    [BOOT_ISSUES]=none
    [PACMAN_ISSUES]=none
    [MIGRATION_ISSUES]=none
    [ISO_ISSUES]=none
    [BROKEN_PACKAGES]=""
    [SEAT_MANAGER]=elogind
    [SEAT_MANAGER_DISABLED]=no
    [HAS_CHAOTIC]=no
    [GPU_DRIVER]=""
    [VM_GUEST]=none
    [DISPLAY_PROTOCOL]=""
    [CPU_UCODE]=none
    [GUM_TITLE_COLOR]=212
    [GUM_ACCENT_COLOR]=34
)

declare -gA STATE_VALIDATORS
STATE_VALIDATORS=(
    [FS_TYPE]="^(ext4|btrfs|xfs|f2fs|zfs)$"
    [INIT]="^(openrc|runit|dinit|s6|busybox)$"
    [BOOTLOADER]="^(grub|refind|efistub|limine|uboot)$"
    [PRIV_ESCALATION]="^(sudo|doas|none)$"
    [X_STACK]="^(xorg|xorg-tearfree|wayland|none)$"
    [USE_LUKS]="^(yes|no)$"
    [USE_LVM]="^(yes|no)$"
    [GENERATE_UKI]="^(yes|no)$"
    [ENABLE_ARCH_REPOS]="^(yes|no)$"
    [ARTIX_BOOT_MODE]="^(uefi|bios)$"
    [SWAP_ENABLED]="^(none|zram|zswap|swapfile)$"
    [MICROCODE_OVERRIDE]="^(auto|intel|amd|none)$"
    [AUDIO_STACK]="^(pipewire|pulseaudio|none)$"
    [NETWORK_STACK]="^(networkmanager|dhcpcd\+iwd|connman|none)$"
    [DISPLAY_MANAGER]="^(sddm|lightdm|gdm|none)$"
)

declare -ga STATE_KEYS_CHROOT
STATE_KEYS_CHROOT=(
    DISK FS_TYPE INIT USE_LUKS USE_LVM GENERATE_UKI BOOTLOADER DISPLAY_MANAGER
    AUDIO_STACK SWAP_ENABLED SWAP_SIZE ZRAM_PERCENT EXTRAS KERNEL_CHOICE
    KERNEL_CONFIG_DEPTH KEEP_BINARY_KERNEL COREUTILS KERNEL_IMAGE
    INITRAMFS_IMAGE MICROCODE_IMAGE MICROCODE_OVERRIDE HOSTNAME TIMEZONE
    LOCALE KEYMAP BTRFS_LAYOUT WM_DE KDE_PROFILE USER_COUNT USER_NAME
    USER_SHELL PRIV_ESCALATION NETWORK_STACK ALLOW_OFFLINE X_STACK
    ENABLE_ARCH_REPOS QUICK_PROFILE PROFILE_PACKAGES QUICK_INSTALL POWER_USER
    POWERUSER_PACKAGES POWERUSER_PROFILE ENABLE_AURIS ARTIX_BOOT_MODE
    LUKS_KEYFILE LUKS_KEYFILE_PATH ISO_ARCH_REPOS GUM_TITLE_COLOR
    GUM_ACCENT_COLOR TKG_SCHEDULER TKG_BINARY TKG_COMPILER TKG_OPTLEVEL
    TKG_PROCESSOR_OPT TKG_LTO_MODE TKG_PREEMPT_RT TKG_TICKLESS
    TKG_TIMER_FREQ TKG_CPU_GOV TKG_GLITCHED_BASE TKG_ZENIFY
    TKG_CLEAR_PATCHES TKG_OPENRGB TKG_ACS_OVERRIDE TKG_FSYNC TKG_MGLRU
    TKG_NTSYNC TKG_NR_CPUS KERNEL_ADV_FS KERNEL_ADV_GPU KERNEL_ADV_NET
    KERNEL_ADV_SOUND KERNEL_ADV_USB KERNEL_ADV_SECURITY KERNEL_ADV_VIRT
    KERNEL_ADV_DEBUG KERNEL_PREEMPT KERNEL_TIMER KERNEL_GOVERNOR
    TARGET_ARCH BOARD_NAME UBOOT_TARGET POST_INSTALL_SCRIPT
)

declare -ga STATE_KEYS_PROFILE
STATE_KEYS_PROFILE=(
    FS_TYPE BOOTLOADER KERNEL_CHOICE INIT PRIV_ESCALATION USE_LUKS USE_LVM
    GENERATE_UKI ALLOW_OFFLINE ENABLE_ARCH_REPOS MICROCODE_OVERRIDE
    KEEP_BINARY_KERNEL COREUTILS KERNEL_CONFIG_DEPTH WM_DE KDE_PROFILE
    DISPLAY_MANAGER NETWORK_STACK AUDIO_STACK X_STACK USER_SHELL EXTRAS
    POWER_USER POWERUSER_PACKAGES POWERUSER_PROFILE ARTIX_BOOT_MODE
    LUKS_KEYFILE ISO_ARCH_REPOS
)

declare -ga STATE_USER_FIELDS
STATE_USER_FIELDS=(NAME PASS SHELL GROUPS SUDO DE DOTFILES)

declare -gA STATE_USER_DEFAULTS
STATE_USER_DEFAULTS=(
    [NAME]=""
    [PASS]=""
    [SHELL]=/bin/bash
    [GROUPS]="wheel,audio,video,storage"
    [SUDO]=yes
    [DE]=""
    [DOTFILES]=""
)

ensure_state_dirs() {
    mkdir -p "${STATE_ROOT}" "${STAGE_DIR}" "${LOG_DIR}"
}

lint_state() {
    local errors=""

    local -a required_keys=(DISK FS_TYPE BOOTLOADER KERNEL_CHOICE INIT)
    local key val
    for key in "${required_keys[@]}"; do
        val=$(state_get "$key" "")
        [[ -n "$val" ]] || errors+="Missing required key: ${key}"$'\n'
    done

    local regex
    for key in "${!STATE_VALIDATORS[@]}"; do
        val=$(state_get "$key" "")
        [[ -n "$val" ]] || continue
        regex="${STATE_VALIDATORS[$key]}"
        if ! [[ "$val" =~ $regex ]]; then
            errors+="${key} '${val}' is not supported"$'\n'
        fi
    done

    local disk
    disk=$(state_get DISK "")
    if [[ -n "$disk" && ! -b "$disk" ]]; then
        errors+="DISK '${disk}' is not a valid block device"$'\n'
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
    local key value ref resolved

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
    if [[ "${user_json}" =~ ^\[.*\]$ ]]; then
        user_count=$(echo "${user_json}" | jq '. | length' 2>/dev/null || echo 0)
    elif [[ "${user_json}" =~ ^[0-9]+$ ]]; then
        user_count="${user_json}"
    else
        user_count=1
    fi

    local key default value
    {
        for key in "${STATE_KEYS[@]}"; do
            default="${STATE_DEFAULTS[$key]:-}"
            if [[ "${key}" == "TKG_NR_CPUS" && -z "$(state_get TKG_NR_CPUS '')" ]]; then
                default="$(nproc)"
            fi
            value="$(state_get "${key}" "${default}")"
            printf '%s=%q\n' "${key}" "${value}"
        done

        local i field
        for ((i=1; i<=user_count; i++)); do
            for field in "${STATE_USER_FIELDS[@]}"; do
                default="${STATE_USER_DEFAULTS[$field]:-}"
                value="$(state_get "USER_${i}_${field}" "${default}")"
                printf 'USER_%d_%s=%q\n' "${i}" "${field}" "${value}"
            done
        done
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
        local raw
        raw=$(grep "^${key}=" "${STATE_FILE}" 2>/dev/null | tail -1 | sed "s|^${key}=||")
        if [[ -n "${raw}" ]]; then
            local value
            value="$(eval "printf '%s' ${raw}" 2>/dev/null)" || value="${raw}"
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

    local escaped
    escaped="$(printf '%q' "${value}")"

    if [[ -f "${STATE_FILE}" ]] && grep -q "^${key}=" "${STATE_FILE}" 2>/dev/null; then
        local tmp="${STATE_FILE}.tmp.$$"
        while IFS= read -r line; do
            if [[ "${line}" =~ ^${key}= ]]; then
                printf '%s=%s\n' "${key}" "${escaped}"
            else
                printf '%s\n' "${line}"
            fi
        done < "${STATE_FILE}" > "${tmp}"
        mv "${tmp}" "${STATE_FILE}"
    else
        printf '%s=%s\n' "${key}" "${escaped}" >> "${STATE_FILE}"
    fi
}

stage_mark_done() {
    ensure_state_dirs
    touch "${STAGE_DIR}/${1}.done"
}

stage_is_done() {
    [[ -f "${STAGE_DIR}/${1}.done" ]]
}

stage_reset() {
    rm -f "${STAGE_DIR}/${1}.done"
}

stage_reset_all() {
    rm -f "${STAGE_DIR}"/*.done
}

stage_log_path() {
    ensure_state_dirs
    printf '%s/%s.log\n' "${LOG_DIR}" "${1}"
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
    local stage="${1}"

    case "${stage}" in
        preflight)  return 0 ;;
        storage)    [[ -b "$(state_get DISK)" ]] ;;
        base)       [[ -x /mnt/usr/bin/bash ]] && artix-chroot /mnt pacman -Q base &>/dev/null ;;
        poweruser)  [[ -f /mnt/etc/artix-poweruser/world.txt ]] && [[ -f /mnt/boot/vmlinuz-linux-custom ]] ;;
        chroot)     [[ -f /mnt/etc/fstab ]] && [[ -f /mnt/etc/hostname ]] ;;
        init)       return 0 ;;
        post)       [[ -d /mnt/home || -d /mnt/root ]] ;;
        finalize)   return 0 ;;
        payload)
            local profile marker
            profile="$(state_get QUICK_PROFILE '')"
            [[ -z "$profile" ]] && return 0
            marker="/mnt/.artixforge-payload-${profile}"
            [[ -f "$marker" ]] || return 1
            [[ -f /mnt/var/lib/pacman/sync/world.db ]] || return 1
            if grep -q '^\[extra\]' /mnt/etc/pacman.conf 2>/dev/null; then
                [[ -f /mnt/var/lib/pacman/sync/extra.db ]] || return 1
            fi
            ;;
        *)          return 1 ;;
    esac
}

stage_reset_from() {
    local stage="${1}"
    local reset='false'
    local current

    for current in \
        preflight \
        storage \
        base \
        poweruser \
        payload \
        chroot \
        init \
        post \
        finalize; do

        if [[ "${current}" == "${stage}" ]]; then
            reset='true'
        fi

        if [[ "${reset}" == 'true' ]]; then
            stage_reset "${current}"
        fi
    done
}

stage_should_skip() {
    local stage="${1}"

    if ! stage_is_done "${stage}"; then
        return 1
    fi

    if ! stage_validate "${stage}"; then
        printf '[!] Stage "%s" marked complete but environment is invalid.\n' "${stage}"
        printf '[!] Resetting stage state...\n'
        stage_reset_from "${stage}"
        return 1
    fi

    printf '[*] %s stage already completed. Skipping...\n' "${stage^}"
    return 0
}