#!/usr/bin/env bash
set -Eeuo pipefail

_clone_dotfiles() {
    local username="${1}" repo_url="${2}"
    [[ -n "${repo_url}" ]] || return 0

    local user_home="/mnt/home/${username}"
    [[ -d "${user_home}" ]] || return 0

    log_info "Cloning dotfiles for ${username} from ${repo_url}..."
    local clone_dir="/tmp/dotfiles-${username}"
    rm -rf "${clone_dir}"
    git clone "${repo_url}" "${clone_dir}" 2>/dev/null || {
        log_warn "Failed to clone dotfiles repo for ${username}"
        return 1
    }

    if [[ -d "${clone_dir}/.config" ]]; then
        mkdir -p "${user_home}/.config"
        cp -a "${clone_dir}/.config/." "${user_home}/.config/" 2>/dev/null || true
    fi

    local item
    for item in "${clone_dir}"/.* "${clone_dir}"/*; do
        [[ -e "${item}" ]] || continue
        local base_name
        base_name=$(basename "${item}")
        [[ "${base_name}" == ".git" || "${base_name}" == ".config" || "${base_name}" == "." || "${base_name}" == ".." ]] && continue
        if [[ -d "${item}" ]]; then
            cp -a "${item}" "${user_home}/" 2>/dev/null || true
        elif [[ -f "${item}" ]]; then
            cp -a "${item}" "${user_home}/" 2>/dev/null || true
        fi
    done

    artix-chroot /mnt chown -R "${username}:${username}" "/home/${username}" 2>/dev/null || true
    rm -rf "${clone_dir}"
    log_info "Dotfiles for ${username} installed."
}

configure_users() {
    local priv_esc wm_de
    priv_esc="$(state_get PRIV_ESCALATION sudo)"
    wm_de="$(state_get WM_DE none)"

    if [[ ${USER_COUNT:-0} -eq 0 ]]; then
        state_set USER_COUNT 1
        state_set USER_1_NAME "artix"
        state_set USER_1_SHELL "/bin/bash"
        state_set USER_1_GROUPS "wheel,audio,video,storage"
        state_set USER_1_SUDO "yes"
        log_warn "No users configured — creating default user 'artix'"
    fi

    local user_count="${USER_COUNT:-1}"

    for ((i=1; i<=user_count; i++)); do
        local username password shell ugroups usudo user_de user_dotfiles
        username="$(state_get "USER_${i}_NAME" "")"
        password="$(state_get "USER_${i}_PASS" "")"
        shell="$(state_get "USER_${i}_SHELL" "/bin/bash")"
        ugroups="$(state_get "USER_${i}_GROUPS" "wheel,audio,video,storage")"
        usudo="$(state_get "USER_${i}_SUDO" "yes")"
        user_de="$(state_get "USER_${i}_DE" "")"
        user_dotfiles="$(state_get "USER_${i}_DOTFILES" "")"

        [[ -n "${username}" ]] || continue
        [[ "${username}" =~ ^[a-z_][a-z0-9_-]*$ ]] || {
            log_warn "Invalid username '${username}' — skipping"
            continue
        }

        case "${shell}" in
            bash) shell="/bin/bash" ;;
            zsh)  shell="/bin/zsh" ;;
            fish) shell="/usr/bin/fish" ;;
        esac
        [[ -x "/mnt${shell}" ]] || shell="/bin/bash"

        local user_hash
        if [[ "${password}" == '$6$'* ]]; then
            user_hash="${password}"
        elif [[ -n "${password}" ]]; then
            user_hash=$(openssl passwd -6 -- "${password}") || {
                log_warn "Failed to hash password for ${username}"
                user_hash=""
            }
        fi

        log_info "Creating user ${username}..."

        local effective_de="${user_de:-${wm_de}}"

        artix-chroot /mnt /bin/bash -c "
set -Eeuo pipefail
if ! id '${username}' &>/dev/null; then
    useradd -m -G '${ugroups//,/ }' -s '${shell}' '${username}'
fi
[[ -n '${user_hash}' ]] && usermod -p '${user_hash}' '${username}'

if [[ '${effective_de}' =~ ^(hyprland|sway|niri|mango|cosmic)$ ]]; then
    usermod -aG seat '${username}'
fi
"

        if [[ "${usudo}" == "yes" ]]; then
            if [[ "${priv_esc}" == "doas" ]]; then
                echo "permit persist ${username}" >> /mnt/etc/doas.conf
            else
                mkdir -p /mnt/etc/sudoers.d
                echo "${username} ALL=(ALL:ALL) ALL" >> /mnt/etc/sudoers.d/99-artixforge
            fi
        fi

        _clone_dotfiles "${username}" "${user_dotfiles}"
    done

    if [[ -f /mnt/etc/sudoers.d/99-artixforge ]]; then
        chmod 440 /mnt/etc/sudoers.d/99-artixforge
    fi
    if [[ -f /mnt/etc/doas.conf ]]; then
        chmod 0400 /mnt/etc/doas.conf
    fi

    if [[ "${priv_esc}" == "sudo" ]]; then
        artix-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
        artix-chroot /mnt sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    fi

    local root_password root_hash
    root_password="$(state_get ROOT_PASS "")"
    if [[ -n "${root_password}" ]]; then
        if [[ "${root_password}" == '$6$'* ]]; then
            root_hash="${root_password}"
        else
            root_hash=$(openssl passwd -6 -- "${root_password}") || die 'failed to hash root password'
        fi
        artix-chroot /mnt usermod -p "${root_hash}" root
        log_info "Root password set."
    fi

    export USER_NAME="${USER_1_NAME:-artix}"

    log_info "User configuration complete."
}