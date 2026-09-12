#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA EXTRA_PACKAGES
EXTRA_PACKAGES=(
    ["git"]="git"
    ["flatpak"]="flatpak"
    ["fastfetch"]="fastfetch"
    ["firewalld"]="firewalld"
    ["bluez"]="bluez"
    ["zram-tools"]="zram-tools"
    ["fzf"]="fzf"
    ["zoxide"]="zoxide"
    ["starship"]="starship"
    ["eza"]="eza"
    ["btop"]="btop"
    ["htop"]="htop"
    ["nvtop"]="nvtop"
    ["tmux"]="tmux"
    ["nano"]="nano"
    ["vim"]="vim"
    ["neovim"]="neovim"
    ["micro"]="micro"
    ["helix"]="helix"
    ["firefox"]="firefox"
    ["chromium"]="chromium"
    ["qutebrowser"]="qutebrowser"
    ["ranger"]="ranger"
    ["lf"]="lf"
    ["nnn"]="nnn"
    ["thunar"]="thunar"
    ["alacritty"]="alacritty"
    ["kitty"]="kitty"
    ["foot"]="foot"
    ["mpv"]="mpv"
    ["feh"]="feh"
)

readonly EXTRAS_SAFETY_FILTER='linux-.*|systemd.*|plasma.*|grub|mkinitcpio|.*-openrc|.*-runit|.*-dinit|.*-s6|sddm|lightdm|gdm|xorg-.*|wayland|hyprland|sway|niri|pipewire|pulseaudio|networkmanager|connman|dhcpcd|efibootmgr|filesystem|pacman|bash|coreutils|util-linux'