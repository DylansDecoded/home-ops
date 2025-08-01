#!/usr/bin/env bash
set -Eeuo pipefail

# Log messages with different levels
function log() {
    local level="${1:-info}"
    shift

    # Define log levels with their priorities
    local level_priority_debug=1
    local level_priority_info=2
    local level_priority_warn=3
    local level_priority_error=4

    # Get the current log level's priority
    local current_priority=2  # Default to "info" priority
    case "$level" in
        debug) current_priority=1 ;;
        info)  current_priority=2 ;;
        warn)  current_priority=3 ;;
        error) current_priority=4 ;;
    esac

    # Get the configured log level from the environment, default to "info"
    local configured_level=${LOG_LEVEL:-info}
    local configured_priority=2  # Default to "info" priority
    case "$configured_level" in
        debug) configured_priority=1 ;;
        info)  configured_priority=2 ;;
        warn)  configured_priority=3 ;;
        error) configured_priority=4 ;;
    esac

    # Skip log messages below the configured log level
    if ((current_priority < configured_priority)); then
        return
    fi

    # Define log colors
    local color_debug="\033[1m\033[38;5;63m"  # Blue
    local color_info="\033[1m\033[38;5;87m"   # Cyan
    local color_warn="\033[1m\033[38;5;192m"  # Yellow
    local color_error="\033[1m\033[38;5;198m" # Red

    # Get the color for the current level
    local color="$color_info"  # Default to info color
    case "$level" in
        debug) color="$color_debug" ;;
        info)  color="$color_info" ;;
        warn)  color="$color_warn" ;;
        error) color="$color_error" ;;
    esac
    local msg="$1"
    shift

    # Prepare additional data
    local data=
    if [[ $# -gt 0 ]]; then
        for item in "$@"; do
            if [[ "${item}" == *=* ]]; then
                data+="\033[1m\033[38;5;236m${item%%=*}=\033[0m\"${item#*=}\" "
            else
                data+="${item} "
            fi
        done
    fi

    # Determine output stream based on log level
    local output_stream="/dev/stdout"
    if [[ "$level" == "error" ]]; then
        output_stream="/dev/stderr"
    fi

    # Print the log message
    printf "%s %b%s%b %s %b\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        "${color}" "$(echo "$level" | tr '[:lower:]' '[:upper:]')" "\033[0m" "${msg}" "${data}" >"${output_stream}"

    # Exit if the log level is error
    if [[ "$level" == "error" ]]; then
        exit 1
    fi
}

# Check if required environment variables are set
function check_env() {
    local envs=("${@}")
    local missing=()
    local values=()

    for env in "${envs[@]}"; do
        if [[ -z "${!env-}" ]]; then
            missing+=("${env}")
        else
            values+=("${env}=${!env}")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log error "Missing required env variables" "envs=${missing[*]}"
    fi

    log debug "Env variables are set" "envs=${values[*]}"
}

# Check if required CLI tools are installed
function check_cli() {
    local deps=("${@}")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            missing+=("${dep}")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log error "Missing required deps" "deps=${missing[*]}"
    fi

    log debug "Deps are installed" "deps=${deps[*]}"
}

# Render a template using minijinja and inject secrets using op
function render_template() {
    local -r file="${1}"
    local output

    if [[ ! -f "${file}" ]]; then
        log error "File does not exist" "file=${file}"
    fi

    if ! output=$(minijinja-cli "${file}" | op inject 2>/dev/null) || [[ -z "${output}" ]]; then
        log error "Failed to render config" "file=${file}"
    fi

    echo "${output}"
}
