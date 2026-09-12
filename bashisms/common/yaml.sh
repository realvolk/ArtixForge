#!/usr/bin/env bash
set -Eeuo pipefail

_yaml_indent_of() {
    local line="$1"
    local stripped="${line#"${line%%[![:space:]]*}"}"
    printf '%d\n' "$(( ${#line} - ${#stripped} ))"
}

_yaml_strip_comment() {
    local line="$1"
    local out="" i ch in_sq=0 in_dq=0
    for ((i=0; i<${#line}; i++)); do
        ch="${line:i:1}"
        if [[ "$ch" == "'" && "$in_dq" -eq 0 ]]; then
            if [[ "$in_sq" -eq 0 ]]; then in_sq=1; else in_sq=0; fi
        elif [[ "$ch" == '"' && "$in_sq" -eq 0 ]]; then
            if [[ "$in_dq" -eq 0 ]]; then in_dq=1; else in_dq=0; fi
        elif [[ "$ch" == "#" && "$in_sq" -eq 0 && "$in_dq" -eq 0 ]]; then
            break
        fi
        out+="$ch"
    done
    printf '%s\n' "$out"
}

_yaml_unquote() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    if [[ "$v" == \"*\" && "$v" == *\" && "${#v}" -ge 2 ]]; then
        v="${v:1:${#v}-2}"
    elif [[ "$v" == \'*\' && "$v" == *\' && "${#v}" -ge 2 ]]; then
        v="${v:1:${#v}-2}"
    fi
    printf '%s\n' "$v"
}

_yaml_key_and_value() {
    local line="$1"
    local stripped="${line#"${line%%[![:space:]]*}"}"
    stripped="${stripped%- }"
    if [[ "$stripped" == -* ]]; then
        _yaml_unquote "${stripped#-}"
        return 0
    fi
    if [[ "$stripped" == *:* ]]; then
        local k="${stripped%%:*}"
        local v="${stripped#*:}"
        printf '%s\t%s\n' "$(_yaml_unquote "$k")" "$(_yaml_unquote "$v")"
        return 0
    fi
    return 1
}

yaml_parse_list() {
    local file="$1" path="$2"
    [[ -f "$file" ]] || return 0

    local -a want
    IFS='.' read -r -a want <<< "$path"
    local want_len="${#want[@]}"

    local -a path_stack=()
    local -a indent_stack=()
    local list_indent=-1
    local in_target=0
    local line indent stripped item

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(_yaml_strip_comment "$line")"
        [[ -z "${line//[[:space:]]/}" ]] && continue
        stripped="${line#"${line%%[![:space:]]*}"}"
        [[ "$stripped" == "---" ]] && continue

        indent="$(_yaml_indent_of "$line")"

        if [[ "$stripped" == -* ]]; then
            if [[ "$in_target" -eq 1 && "$indent" -eq "$list_indent" ]]; then
                item="$(_yaml_unquote "${stripped#-}")"
                [[ -n "$item" ]] && printf '%s\n' "$item"
            fi
            continue
        fi

        while [[ "${#indent_stack[@]}" -gt 0 && "${indent_stack[-1]}" -ge "$indent" ]]; do
            indent_stack=("${indent_stack[@]:0:${#indent_stack[@]}-1}")
            if [[ "${#path_stack[@]}" -gt 0 ]]; then
                path_stack=("${path_stack[@]:0:${#path_stack[@]}-1}")
            fi
        done

        local kv
        if ! kv="$(_yaml_key_and_value "$line")"; then
            continue
        fi
        local k="${kv%%$'\t'*}"
        local v="${kv#*$'\t'}"

        path_stack+=("$k")
        indent_stack+=("$indent")

        if [[ "${#path_stack[@]}" -eq "$want_len" ]]; then
            local i match=1
            for ((i=0; i<want_len; i++)); do
                [[ "${path_stack[i]}" == "${want[i]}" ]] || { match=0; break; }
            done
            if [[ "$match" -eq 1 ]]; then
                if [[ -n "$v" ]]; then
                    printf '%s\n' "$v"
                    in_target=0
                else
                    in_target=1
                    list_indent=-1
                fi
            else
                in_target=0
            fi
        else
            in_target=0
        fi

        if [[ "$in_target" -eq 1 ]]; then
            list_indent=$(( indent + 2 ))
        fi
    done < "$file"
}

yaml_parse_scalar() {
    local file="$1" path="$2"
    [[ -f "$file" ]] || return 0

    local -a want
    IFS='.' read -r -a want <<< "$path"
    local want_len="${#want[@]}"

    local -a path_stack=()
    local -a indent_stack=()
    local line indent stripped

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(_yaml_strip_comment "$line")"
        [[ -z "${line//[[:space:]]/}" ]] && continue
        stripped="${line#"${line%%[![:space:]]*}"}"
        [[ "$stripped" == "---" ]] && continue
        [[ "$stripped" == -* ]] && continue

        indent="$(_yaml_indent_of "$line")"

        while [[ "${#indent_stack[@]}" -gt 0 && "${indent_stack[-1]}" -ge "$indent" ]]; do
            indent_stack=("${indent_stack[@]:0:${#indent_stack[@]}-1}")
            if [[ "${#path_stack[@]}" -gt 0 ]]; then
                path_stack=("${path_stack[@]:0:${#path_stack[@]}-1}")
            fi
        done

        local kv
        if ! kv="$(_yaml_key_and_value "$line")"; then
            continue
        fi
        local k="${kv%%$'\t'*}"
        local v="${kv#*$'\t'}"

        path_stack+=("$k")
        indent_stack+=("$indent")

        if [[ "${#path_stack[@]}" -eq "$want_len" && -n "$v" ]]; then
            local i match=1
            for ((i=0; i<want_len; i++)); do
                [[ "${path_stack[i]}" == "${want[i]}" ]] || { match=0; break; }
            done
            if [[ "$match" -eq 1 ]]; then
                printf '%s\n' "$v"
                return 0
            fi
        fi
    done < "$file"
}