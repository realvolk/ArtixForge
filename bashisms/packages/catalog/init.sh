#!/usr/bin/env bash
set -Eeuo pipefail

declare -gA INIT_PACKAGES
INIT_PACKAGES=(
    [openrc]="openrc openrc-settingsd"
    [runit]="runit runit-rc"
    [dinit]="dinit dinit-base dinit-rc"
    [s6]="s6 s6-rc s6-base"
    [busybox]=""
)

declare -gA INIT_SUFFIX
INIT_SUFFIX=(
    [openrc]=openrc
    [runit]=runit
    [dinit]=dinit
    [s6]=s6
    [busybox]=""
)

declare -gA INIT_FALLBACK_PACKAGES
INIT_FALLBACK_PACKAGES=(
    [openrc]="openrc openrc-settingsd elogind-openrc"
    [runit]="runit runit-rc elogind-runit"
    [dinit]="dinit dinit-base dinit-rc elogind-dinit"
    [s6]="s6 s6-rc s6-base elogind-s6"
)

declare -gA INIT_ELOGIND
INIT_ELOGIND=(
    [openrc]="elogind-openrc"
    [runit]="elogind-runit"
    [dinit]="elogind-dinit"
    [s6]="elogind-s6"
)

declare -ga INIT_LIST
INIT_LIST=(openrc runit dinit s6 busybox)