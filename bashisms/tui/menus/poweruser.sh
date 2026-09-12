#!/usr/bin/env bash
set -Eeuo pipefail

tui_select_poweruser() {
    [[ "$(state_get POWER_USER no)" == "yes" ]] || return 0

    POWERUSER_DIR="${BASE_DIR}/poweruser"
    source "${POWERUSER_DIR}/lib/flags.bash"
    source "${POWERUSER_DIR}/lib/recipe.bash"
    source "${POWERUSER_DIR}/tui/menu_poweruser.sh"

    local recipe_count
    recipe_count=$(find "${POWERUSER_DIR}/recipes" -name '*.sh' ! -name 'template.sh' | wc -l)
    if [[ ${recipe_count} -eq 0 ]]; then
        log_info "No recipes found. Fetching OFFICIAL/Base..."
        local list_url="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main/.LIST"
        local repo_base="https://raw.githubusercontent.com/realvolk/ArtixForge-recipes/main"
        if curl -fsSL "${list_url}" -o /tmp/artix-recipes.list 2>/dev/null; then
            while IFS='|' read -r name section desc; do
                if [[ "${section}" == "OFFICIAL/Base" ]]; then
                    log_info "  Downloading ${name}.sh..."
                    curl -sL "${repo_base}/${section}/${name}.sh" -o "${POWERUSER_DIR}/recipes/${name}.sh" || log_warn "Failed to download ${name}"
                fi
            done < /tmp/artix-recipes.list
            rm -f /tmp/artix-recipes.list
            log_info "Recipes downloaded."
        fi
    fi

    tui_poweruser_config
}