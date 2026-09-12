#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA DE_PACKAGES
DE_PACKAGES=(
    [kde-minimal]="plasma-desktop dolphin konsole xdg-desktop-portal-kde sddm sddm-@init@"
    [kde-desktop]="plasma xdg-desktop-portal-kde sddm sddm-@init@"
    [kde-full]="plasma kde-applications xdg-desktop-portal-kde sddm sddm-@init@"
    [xfce4]="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter lightdm-@init@"
    [lxqt]="lxqt sddm sddm-@init@"
    [lxde]="lxde lxappearance lightdm lightdm-gtk-greeter lightdm-@init@"
    [mate]="mate mate-extra lightdm lightdm-gtk-greeter lightdm-@init@ xdg-desktop-portal-gtk"
    [cinnamon]="cinnamon lightdm lightdm-gtk-greeter lightdm-@init@ xdg-desktop-portal-gtk"
    [budgie]="budgie-desktop budgie-screensaver budgie-control-center lightdm lightdm-gtk-greeter lightdm-@init@ xdg-desktop-portal-gtk"
    [moksha]="moksha terminology lightdm lightdm-gtk-greeter lightdm-@init@"
    [cosmic]="cosmic cosmic-terminal cosmic-text-editor cosmic-files cosmic-settings cosmic-launcher lightdm lightdm-gtk-greeter lightdm-@init@"
    [hyprland]="hyprland foot waybar wofi xdg-desktop-portal-hyprland seatd seatd-@init@ xorg-xwayland"
    [sway]="sway swaybg swaylock swayidle foot waybar wofi xdg-desktop-portal-wlr seatd seatd-@init@ xorg-xwayland"
    [niri]="niri foot waybar fuzzel xdg-desktop-portal-gtk seatd seatd-@init@ xorg-xwayland"
    [i3wm]="i3-wm i3status i3lock dmenu xterm lightdm lightdm-gtk-greeter lightdm-@init@"
    [dwm]="dwm dmenu xterm lightdm lightdm-gtk-greeter lightdm-@init@"
    [icewm]="icewm icewm-themes xterm lightdm lightdm-gtk-greeter lightdm-@init@"
    [mango]=""
    [vxwm]=""
    [none]=""
)

declare -gA DE_DISPLAY_MANAGER
DE_DISPLAY_MANAGER=(
    [kde]=sddm
    [xfce4]=lightdm
    [lxqt]=sddm
    [lxde]=lightdm
    [mate]=lightdm
    [cinnamon]=lightdm
    [budgie]=lightdm
    [moksha]=lightdm
    [cosmic]=lightdm
    [i3wm]=lightdm
    [dwm]=lightdm
    [icewm]=lightdm
    [hyprland]=none
    [sway]=none
    [niri]=none
    [mango]=none
    [vxwm]=none
    [none]=none
)

declare -gA DE_DISPLAY_SERVER
DE_DISPLAY_SERVER=(
    [kde]=both
    [xfce4]=xorg
    [lxqt]=xorg
    [lxde]=xorg
    [mate]=xorg
    [cinnamon]=xorg
    [budgie]=xorg
    [moksha]=xorg
    [cosmic]=wayland
    [hyprland]=wayland
    [sway]=wayland
    [niri]=wayland
    [mango]=wayland
    [i3wm]=xorg
    [dwm]=xorg
    [icewm]=xorg
    [vxwm]=xorg
)

declare -gA DE_TOOLKIT
DE_TOOLKIT=(
    [kde]=qt
    [lxqt]=qt
    [xfce4]=gtk
    [lxde]=gtk
    [mate]=gtk
    [cinnamon]=gtk
    [budgie]=gtk
    [moksha]=gtk
    [cosmic]=gtk
)

declare -gA DE_PRETTY_NAME
DE_PRETTY_NAME=(
    [kde]="KDE Plasma"
    [xfce4]="XFCE"
    [lxqt]="LXQt"
    [lxde]="LXDE"
    [mate]="MATE"
    [cinnamon]="Cinnamon"
    [budgie]="Budgie"
    [moksha]="Moksha"
    [cosmic]="COSMIC"
    [hyprland]="Hyprland"
    [sway]="Sway"
    [niri]="Niri"
    [i3wm]="i3"
    [dwm]="dwm"
    [vxwm]="vxwm"
    [icewm]="IceWM"
    [mango]="MangoWM"
    [none]="None"
)

declare -gA DE_TO_PROFILE
DE_TO_PROFILE=(
    [kde]=plasma
    [xfce4]=xfce
    [lxqt]=lxqt
    [lxde]=lxde
    [mate]=mate
    [cinnamon]=cinnamon
    [budgie]=budgie
    [moksha]=moksha
    [cosmic]=cosmic
    [hyprland]=hyprland
    [sway]=sway
    [niri]=niri
    [i3wm]=i3wm
    [dwm]=dwm
    [icewm]=icewm
    [mango]=mango
    [vxwm]=base
)

declare -gA PROFILE_TOOLKIT
PROFILE_TOOLKIT=(
    [plasma]=qt
    [community-qt]=qt
    [lxqt]=qt
    [xfce]=gtk
    [lxde]=gtk
    [mate]=gtk
    [cinnamon]=gtk
    [budgie]=gtk
    [moksha]=gtk
    [community-gtk]=gtk
    [community]=gtk
)

declare -gA DE_SEAT_PACKAGE
DE_SEAT_PACKAGE=(
    [hyprland]=seatd
    [sway]=seatd
    [niri]=seatd
    [mango]=seatd
    [cosmic]=seatd
)

declare -gA DE_DETECT_PATTERN
DE_DETECT_PATTERN=(
    [kde]='^(plasma|plasma-|kwin|kde-|sddm|dolphin|konsole|kate|okular|gwenview|spectacle|discover|drkonqi|bluedevil|xdg-desktop-portal-kde)'
    [xfce4]='^(xfce4|xfce4-|xfdesktop|xfwm4|thunar|tumbler|ristretto|mousepad|orage)'
    [lxqt]='^(lxqt|lxqt-|pcmanfm-qt|qterminal|sddm)'
    [lxde]='^(lxde|lxde-|lxsession|pcmanfm)'
    [mate]='^(mate|mate-|caja|pluma|engrampa|atril|marco|eom)'
    [cinnamon]='^(cinnamon|cinnamon-|muffin|nemo)'
    [budgie]='^(budgie|budgie-|gnome-shell)'
    [moksha]='^(moksha|enlightenment|terminology)'
    [cosmic]='^(cosmic)'
    [hyprland]='^(hyprland|hypr|xdg-desktop-portal-hyprland)'
    [sway]='^(sway|swaybg|swaylock|swayidle|wofi|waybar)'
    [niri]='^(niri|fuzzel)'
    [i3wm]='^(i3-wm|i3status|i3lock|dmenu)'
    [dwm]='^(dwm|dmenu)'
    [vxwm]='^(vxwm)'
    [icewm]='^(icewm|icewm-)'
    [mango]='^(mangowm|mangowm-)'
)

declare -ga DE_DETECT_ORDER
DE_DETECT_ORDER=(
    hyprland sway niri mango cosmic
    kde xfce4 lxqt lxde mate cinnamon budgie moksha
    i3wm dwm vxwm icewm
)

declare -ga DE_INSTALL_LIST
DE_INSTALL_LIST=(
    kde xfce4 lxqt lxde mate cinnamon budgie moksha cosmic
    hyprland sway niri i3wm dwm icewm mango vxwm none
)

declare -ga DE_MIGRATION_TARGETS
DE_MIGRATION_TARGETS=(
    kde xfce4 lxqt lxde mate hyprland sway niri
    i3wm dwm vxwm icewm mango none
)

declare -ga DE_MIGRATION_SOURCES
DE_MIGRATION_SOURCES=(
    kde xfce4 lxqt lxde mate hyprland sway niri
    i3wm dwm vxwm icewm mango sonicde none
)