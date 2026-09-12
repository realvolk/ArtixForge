#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA AUDIO_PACKAGES
AUDIO_PACKAGES=(
    [pipewire]="pipewire pipewire-pulse pipewire-alsa wireplumber alsa-utils pavucontrol rtkit pipewire-jack"
    [pulseaudio]="pulseaudio pulseaudio-alsa alsa-utils pavucontrol"
    [none]=""
)

declare -gA AUDIO_SERVICE_PACKAGES
AUDIO_SERVICE_PACKAGES=(
    [pipewire-openrc]="pipewire-openrc pipewire-pulse-openrc wireplumber-openrc"
    [pipewire-dinit]="pipewire-dinit pipewire-pulse-dinit wireplumber-dinit"
    [pulseaudio-openrc]="pulseaudio-openrc"
    [pulseaudio-dinit]="pulseaudio-dinit"
)

declare -gA AUDIO_CONFLICTS
AUDIO_CONFLICTS=(
    [pipewire]="pulseaudio pulseaudio-alsa jack2"
    [pulseaudio]="pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber"
)