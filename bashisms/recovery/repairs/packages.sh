#!/usr/bin/env bash
set -Eeuo pipefail

repair_pacman() {
    if ! artix-chroot "${ROOT}" true &>/dev/null; then
        log_warn "Chroot environment not available — skipping pacman repairs"
        return 0
    fi

    local issues
    issues=$(state_get PACMAN_ISSUES none)

    if [[ "${issues}" =~ stale-lock ]]; then
        log_warn "Pacman lock found."
        if tui_yesno "Remove lock" "Remove stale pacman lock?"; then
            rm -f "${ROOT}/var/lib/pacman/db.lck"
            log_info "Lock removed."
        fi
    fi

    if [[ "${issues}" =~ base-missing ]]; then
        log_warn "Base system packages missing or corrupted."
        if tui_yesno "Reinstall base" "Reinstall base packages?"; then
            if ! basestrap "${ROOT}" base base-devel 2>/dev/null; then
                log_warn "basestrap failed — trying direct pacman install..."
                pacman --root "${ROOT}" --cachedir "${ROOT}/var/cache/pacman/pkg" \
                    -S --noconfirm base base-devel 2>/dev/null || \
                    log_warn "Base reinstall failed. Try 'Fix everything' from the recovery menu."
            fi
            log_info "Base packages reinstalled."
        fi
    fi

    if [[ "${issues}" =~ broken-pkgs:([0-9]+) ]]; then
        local count="${BASH_REMATCH[1]}"
        log_warn "${count} packages have missing files."
        if tui_yesno "Repair broken packages" "Reinstall all packages with missing files? This may take a while."; then
            local broken_list
            broken_list="$(state_get BROKEN_PACKAGES "")"
            if [[ -n "${broken_list}" ]]; then
                log_info "Reinstalling ${count} broken packages..."
                local -a pkgs
                read -ra pkgs <<< "${broken_list}"
                local batch=() i=0 success=0 fail=0
                for pkg in "${pkgs[@]}"; do
                    batch+=("${pkg}")
                    ((i++))
                    if [[ ${i} -ge 20 ]]; then
                        local batch_size=${#batch[@]}
                        log_info "  Batch: ${batch[*]}"
                        if pacman --root "${ROOT}" --cachedir "${ROOT}/var/cache/pacman/pkg" \
                                -S --noconfirm --overwrite '*' "${batch[@]}" 2>/dev/null; then
                            ((success += batch_size))
                        else
                            log_warn "  Batch failed — trying individually..."
                            for b in "${batch[@]}"; do
                                if pacman --root "${ROOT}" -S --noconfirm --overwrite '*' "${b}" 2>/dev/null; then
                                    ((success++))
                                else
                                    log_warn "  Failed: ${b}"
                                    ((fail++))
                                fi
                            done
                        fi
                        batch=() i=0
                    fi
                done

                if [[ ${#batch[@]} -gt 0 ]]; then
                    local batch_size=${#batch[@]}
                    log_info "  Final batch: ${batch[*]}"
                    if pacman --root "${ROOT}" --cachedir "${ROOT}/var/cache/pacman/pkg" \
                            -S --noconfirm --overwrite '*' "${batch[@]}" 2>/dev/null; then
                        ((success += batch_size))
                    else
                        for b in "${batch[@]}"; do
                            if pacman --root "${ROOT}" -S --noconfirm --overwrite '*' "${b}" 2>/dev/null; then
                                ((success++))
                            else
                                log_warn "  Failed: ${b}"
                                ((fail++))
                            fi
                        done
                    fi
                fi
                log_info "Reinstall complete: ${success} succeeded, ${fail} failed"
            else
                log_info "No broken package list saved — skipping"
            fi
            log_info "Broken package repair completed."
        fi
    fi

    if [[ "${issues}" =~ partial-downloads:([0-9]+) ]]; then
        local count="${BASH_REMATCH[1]}"
        log_warn "${count} partial download(s) found in pacman cache."
        if tui_yesno "Partial Downloads" "Remove ${count} partial .part file(s)?"; then
            find "${ROOT}/var/cache/pacman/pkg" -maxdepth 1 -name '*.part' -delete
            log_info "Removed partial downloads."
        fi
    fi

    if [[ "${issues}" =~ incomplete-packages:([0-9]+) ]]; then
        local count="${BASH_REMATCH[1]}"
        log_warn "${count} package(s) with incomplete metadata."
        if tui_yesno "Incomplete Packages" "List and reinstall them?"; then
            local pkgdir pkgname
            local -a broken_meta=()
            for pkgdir in "${ROOT}"/var/lib/pacman/local/*/; do
                [[ -d "${pkgdir}" ]] || continue
                [[ -f "${pkgdir}/desc" ]] || continue
                if [[ ! -f "${pkgdir}/files" ]]; then
                    pkgname=$(basename "${pkgdir}")
                    broken_meta+=("${pkgname%-*-*}")
                fi
            done
            if [[ ${#broken_meta[@]} -gt 0 ]]; then
                log_info "Reinstalling: ${broken_meta[*]}"
                pacman --root "${ROOT}" --cachedir "${ROOT}/var/cache/pacman/pkg" \
                    -S --noconfirm "${broken_meta[@]}" 2>/dev/null || \
                    log_warn "Reinstall failed — try refreshing mirrors and retry"
            fi
        fi
    fi

    if [[ "${issues}" =~ interrupted-transaction ]]; then
        log_warn "Last pacman transaction did not complete."
        if tui_yesno "Interrupted Upgrade" "Re-sync databases and reinstall half-updated packages?"; then
            artix-chroot "${ROOT}" pacman -Syu --noconfirm || \
                log_warn "Full upgrade failed — check output above"
        fi
    fi
}

detect_rootkits() {
    if ! command -v rkhunter &>/dev/null; then
        pacman -S --noconfirm rkhunter
    fi
    rkhunter --check --skip-keypress 2>&1 | tee /tmp/rkhunter.log
    if grep -q 'Warning' /tmp/rkhunter.log; then
        log_warn "Rootkit warnings found. Review /tmp/rkhunter.log"
    else
        log_info "No rootkit warnings detected."
    fi
}