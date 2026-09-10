#!/usr/bin/env bash
set -Eeuo pipefail

tui_select_username() {
    local u
    u=$(tui_input "Username" "Enter username:" "artix") || return 1
    u="${u//[$'\r'$'\n'$'\t' ]/}"
    [[ -n "${u}" ]] || return 1
    state_set USER_NAME "${u}"
}

tui_select_user_password() {
    local pass
    pass=$(tui_password_confirm "User Password" "Enter user password:" "Confirm password:") || return 1
    state_set USER_PASS "${pass}"
}

tui_select_root_password() {
    local pass
    pass=$(tui_password_confirm "Root Password" "Enter root password:" "Confirm password:") || return 1
    state_set ROOT_PASS "${pass}"
}

tui_configure_users() {
    USER_COUNT="${USER_COUNT:-0}"
    state_set USER_COUNT "${USER_COUNT}"

    while true; do
        local choice
        choice=$(tui_menu "User Management" "Manage user accounts:" \
            "Add a user" \
            "Edit a user" \
            "Remove a user" \
            "Done – return to installer") || break

        case "${choice}" in
            "Add a user"*)
                tui_add_user
                ;;
            "Edit a user"*)
                tui_edit_user
                ;;
            "Remove a user"*)
                tui_remove_user
                ;;
            "Done"*)
                break
                ;;
        esac
    done

    if [[ ${USER_COUNT:-0} -eq 0 ]]; then
        tui_msg_quick "No Users" "At least one user account is required."
        tui_add_user
    fi

    if ! tui_yesno "Root Password" "Set a root password?"; then
        state_set ROOT_PASS ""
    else
        tui_select_root_password
    fi
}

tui_add_user() {
    local idx=$(( ${USER_COUNT:-0} + 1 ))
    tui_edit_user_dialog "${idx}" "new"
}

tui_edit_user() {
    if [[ ${USER_COUNT:-0} -eq 0 ]]; then
        tui_msg_quick "No Users" "No users to edit."
        return
    fi
    local -a user_list
    for ((i=1; i<=${USER_COUNT}; i++)); do
        user_list+=("User ${i}: $(state_get "USER_${i}_NAME" "unnamed")")
    done
    local chosen
    chosen=$(tui_menu "Edit User" "Select a user to edit:" "${user_list[@]}") || return
    local idx="${chosen%%:*}"
    idx="${idx#User }"
    tui_edit_user_dialog "${idx}" "edit"
}

tui_remove_user() {
    if [[ ${USER_COUNT:-0} -eq 0 ]]; then
        tui_msg_quick "No Users" "No users to remove."
        return
    fi
    local -a user_list
    for ((i=1; i<=${USER_COUNT}; i++)); do
        user_list+=("User ${i}: $(state_get "USER_${i}_NAME" "unnamed")")
    done
    local chosen
    chosen=$(tui_menu "Remove User" "Select a user to remove:" "${user_list[@]}") || return
    local idx="${chosen%%:*}"
    idx="${idx#User }"
    if tui_yesno "Confirm Removal" "Remove $(state_get "USER_${idx}_NAME" "this user")?"; then
        for ((i=idx; i<${USER_COUNT}; i++)); do
            local next=$((i+1))
            state_set "USER_${i}_NAME"     "$(state_get "USER_${next}_NAME" "")"
            state_set "USER_${i}_PASS"     "$(state_get "USER_${next}_PASS" "")"
            state_set "USER_${i}_SHELL"    "$(state_get "USER_${next}_SHELL" "/bin/bash")"
            state_set "USER_${i}_GROUPS"   "$(state_get "USER_${next}_GROUPS" "wheel,audio,video,storage")"
            state_set "USER_${i}_SUDO"     "$(state_get "USER_${next}_SUDO" "yes")"
            state_set "USER_${i}_DE"       "$(state_get "USER_${next}_DE" "")"
            state_set "USER_${i}_DOTFILES" "$(state_get "USER_${next}_DOTFILES" "")"
        done
        USER_COUNT=$((USER_COUNT - 1))
        state_set USER_COUNT "${USER_COUNT}"
        for key in NAME PASS SHELL GROUPS SUDO DE DOTFILES; do
            state_set "USER_${USER_COUNT}_${key}" ""
        done
        log_info "User ${idx} removed."
    fi
}

tui_edit_user_dialog() {
    local idx="${1}" mode="${2}"
    local current_name="$(state_get "USER_${idx}_NAME" "")"
    
    local name
    name=$(tui_input "Username" "Enter username:" "${current_name}") || return
    [[ -n "${name}" ]] || { tui_msg_quick "Invalid" "Username cannot be empty."; return; }

    local pass
    pass=$(tui_password_confirm "User Password" "Enter password for ${name}:" "Confirm password:") || return
    if [[ -n "${pass}" ]]; then
        pass=$(openssl passwd -6 -- "${pass}") || { log_error "Failed to hash password"; return; }
    fi

    local current_shell="$(state_get "USER_${idx}_SHELL" "/bin/bash")"
    local shell
    shell=$(tui_menu "User Shell" "Select default shell for ${name}:" "bash" "zsh" "fish") || shell="bash"
    case "${shell}" in
        bash) shell="/bin/bash" ;;
        zsh)  shell="/bin/zsh" ;;
        fish) shell="/usr/bin/fish" ;;
    esac

    local current_groups="$(state_get "USER_${idx}_GROUPS" "wheel,audio,video,storage")"
    local groups
    groups=$(tui_checklist "User Groups" "Select groups for ${name}:" \
        "wheel" "audio" "video" "storage" "lp" "network" "optical" "scanner" "users") || groups="${current_groups}"
    groups="${groups//$'\n'/,}"
    [[ -z "${groups// /}" ]] && groups="${current_groups}"

    local current_sudo="$(state_get "USER_${idx}_SUDO" "yes")"
    local sudo_choice
    sudo_choice=$(tui_menu "Sudo Access" "Grant sudo privileges to ${name}?" "Yes" "No") || sudo_choice="Yes"
    [[ "${sudo_choice}" == "Yes" ]] && sudo_choice="yes" || sudo_choice="no"

    local current_de="$(state_get "USER_${idx}_DE" "")"
    local de_choice
    de_choice=$(tui_menu "User Desktop" "Select desktop for ${name} (or inherit system default):" \
        "Inherit system default" \
        "kde" "xfce4" "lxqt" "lxde" "mango" "hyprland" "niri" "sway" \
        "i3wm" "dwm" "vxwm" "icewm" "cinnamon" "budgie" "moksha" "cosmic" "none") || de_choice="Inherit system default"
    [[ "${de_choice}" == "Inherit system default" ]] && de_choice=""

    local current_dotfiles="$(state_get "USER_${idx}_DOTFILES" "")"
    local dotfiles
    dotfiles=$(tui_input "Dotfiles Repo" "Enter dotfiles repo URL for ${name} (optional):" "${current_dotfiles}") || dotfiles="${current_dotfiles}"

    state_set "USER_${idx}_NAME"     "${name}"
    state_set "USER_${idx}_PASS"     "${pass}"
    state_set "USER_${idx}_SHELL"    "${shell}"
    state_set "USER_${idx}_GROUPS"   "${groups}"
    state_set "USER_${idx}_SUDO"     "${sudo_choice}"
    state_set "USER_${idx}_DE"       "${de_choice}"
    state_set "USER_${idx}_DOTFILES" "${dotfiles}"

    if [[ "${mode}" == "new" ]]; then
        USER_COUNT="${idx}"
        state_set USER_COUNT "${USER_COUNT}"
        log_info "User ${name} added."
    else
        log_info "User ${name} updated."
    fi
}

tui_select_hostname() {
    local h
    while true; do
        h=$(tui_input "Hostname" "Enter system hostname:" "artix") || return 1
        h="${h//[$'\r'$'\n'$'\t' ]/}"
        [[ -n "${h}" ]] || return 1
        if [[ "${h}" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]*$ ]]; then
            state_set HOSTNAME "${h}"
            return 0
        fi
        tui_msg_quick "Invalid Hostname" "Allowed: a-z, A-Z, 0-9, dash. Start with letter/digit."
    done
}

tui_select_timezone() {
    local items tz
    items=$(find /usr/share/zoneinfo -type f 2>/dev/null | sed 's|/usr/share/zoneinfo/||' | grep -v '^posix\|^right\|^Etc\|\.tab$' | sort)
    tz=$(printf '%s\n' "${items}" | tui_filter "Timezone" "Type to search (e.g. Europe)..." --placeholder "Europe/London") || tz="Europe/Belgrade"
    [[ -n "${tz}" ]] || tz="Europe/Belgrade"
    state_set TIMEZONE "${tz}"
}

tui_select_locale() {
    local items l
    items=$(grep -E '^#?[a-z]{2}_[A-Z]{2}.*UTF-8' /etc/locale.gen 2>/dev/null | sed 's/^#//' | awk '{print $1}' | sort -u)
    l=$(printf '%s\n' "${items}" | tui_filter "Locale" "Type to search (e.g. en_US)..." --placeholder "en_US.UTF-8") || l="en_US.UTF-8"
    [[ -n "${l}" ]] || l="en_US.UTF-8"
    state_set LOCALE "${l}"
}

tui_select_priv_escalation() {
    local priv
    priv=$(tui_menu "Privilege Escalation" "Select privilege escalation tool:" \
        "sudo" "doas") || return 1
    state_set PRIV_ESCALATION "${priv,,}"
}

tui_select_keyboard_layout() {
    local k items
    items=$(localectl list-keymaps 2>/dev/null || find /usr/share/kbd/keymaps -name '*.map.gz' 2>/dev/null | sed 's|.*/||; s|\.map\.gz||' | sort -u)
    k=$(printf '%s\n' "${items}" | tui_filter "Keyboard Layout" "Type to search (e.g. us, de, fr)..." --placeholder "us") || k="us"
    [[ -n "${k}" ]] || k="us"
    state_set KEYMAP "${k}"
}

tui_select_shell() {
    local s
    s=$(tui_menu "User Shell" "Select default shell:" "bash" "zsh" "fish") || return 1
    state_set USER_SHELL "${s}"
}

tui_select_microcode() {
    local detected='amd-ucode'
    if [[ "$(< /proc/cpuinfo)" == *GenuineIntel* ]]; then
        detected='intel-ucode'
    fi

    if tui_yesno "CPU Microcode" "Detected ${detected}. Use automatically?"; then
        state_set MICROCODE_OVERRIDE "${detected}"
        return 0
    fi
    local u
    if ! u=$(tui_menu "CPU Microcode" "Select microcode:" "amd-ucode" "intel-ucode" "none" 2>/dev/null); then
        log_warn "Microcode selection menu failed — defaulting to amd-ucode"
        u="amd-ucode"
    fi
    state_set MICROCODE_OVERRIDE "${u}"
}