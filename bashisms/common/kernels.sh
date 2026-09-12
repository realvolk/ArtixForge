#!/usr/bin/env bash
set -Eeuo pipefail;

detect_kernel_package() {
    local kernel="${1:-linux}";

    KERNEL_PACKAGE='';
    KERNEL_HEADERS='';
    KERNEL_AUR='false';

    # ARM64 kernels from ARMtix
    case "${kernel}" in
        linux-aarch64)
            KERNEL_PACKAGE='linux-aarch64';
            KERNEL_HEADERS='linux-aarch64-headers';
            return 0 ;;
        linux-aarch64-lts)
            KERNEL_PACKAGE='linux-aarch64-lts';
            KERNEL_HEADERS='linux-aarch64-lts-headers';
            return 0 ;;
        linux-radxa)
            KERNEL_PACKAGE='linux-radxa';
            KERNEL_HEADERS='linux-radxa-headers';
            return 0 ;;
    esac

    case "${kernel}" in
        linux)
            KERNEL_PACKAGE='linux';
            KERNEL_HEADERS='linux-headers';
            ;;

        linux-lts)
            KERNEL_PACKAGE='linux-lts';
            KERNEL_HEADERS='linux-lts-headers';
            ;;

        linux-hardened)
            KERNEL_PACKAGE='linux-hardened';
            KERNEL_HEADERS='linux-hardened-headers';
            ;;

        linux-zen)
            KERNEL_PACKAGE='linux-zen';
            KERNEL_HEADERS='linux-zen-headers';
            ;;

        linux-libre)
            KERNEL_PACKAGE='linux-libre';
            KERNEL_HEADERS='linux-libre-headers';
            ;;

        linux-cachyos*)
            KERNEL_PACKAGE="${kernel}";
            KERNEL_HEADERS="${kernel}-headers";
            ;;

        linux-bazzite-bin)
            KERNEL_AUR='true';
            ;;

        xanmod)
            local cpu_level;

            cpu_level=$(
                /lib/ld-linux-x86-64.so.2 --help \
                    | grep -E 'x86-64-v[2-4] \(supported' \
                    | head -n1 \
                    | awk '{print $1}'
            );

            case "${cpu_level}" in
                x86-64-v4)
                    KERNEL_PACKAGE='linux-xanmod-x64v4';
                    ;;

                x86-64-v3)
                    KERNEL_PACKAGE='linux-xanmod-x64v3';
                    ;;

                x86-64-v2)
                    KERNEL_PACKAGE='linux-xanmod-x64v2';
                    ;;

                *)
                    KERNEL_PACKAGE='linux-xanmod';
                    ;;
            esac

            KERNEL_HEADERS="${KERNEL_PACKAGE}-headers";
            ;;
        tkg)
            KERNEL_AUR='true'
            KERNEL_PACKAGE=""
            KERNEL_HEADERS=""
            ;;

        *)
            die "unsupported kernel: ${kernel}";
            ;;
    esac

    if [[ "${KERNEL_AUR}" != 'true' ]]; then
        [[ -n "${KERNEL_PACKAGE}" ]] \
            || die 'failed to detect kernel package';
        [[ -n "${KERNEL_HEADERS}" ]] \
            || die 'failed to detect kernel headers';
    fi
}