#!/usr/bin/env bash
set -Eeuo pipefail

tui_select_network_stack() {
    local ns
    ns=$(tui_menu "Networking" "Select network stack:" \
        "NetworkManager" "dhcpcd+iwd" "ConnMan" "None") || return 1
    state_set NETWORK_STACK "${ns,,}"
}

tui_select_audio_stack() {
    local as
    as=$(tui_menu "Audio" "Select audio stack:" "PipeWire" "PulseAudio" "None") || return 1
    state_set AUDIO_STACK "${as,,}"
}