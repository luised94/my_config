#!/bin/bash

[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "${BASH_SOURCE%/*}/../init.sh"

setup_aliases() {
    log_info "Setting up aliases..."
    
    # Basic aliases
    for alias_def in "${BASIC_ALIASES[@]}"; do
        alias "${alias_def}"
    done

    # Git aliases
    for alias_def in "${GIT_ALIASES[@]}"; do
        alias "${alias_def}"
    done

    # Lab utils repo aliases
    for alias_def in "${LABUTILS_ALIASES[@]}"; do
        alias "${alias_def}"
    done

    log_info "Aliases configured successfully"
}

setup_environment() {
    log_info "Setting up environment..."
    
    # Add additional paths
    for path in "${ADDITIONAL_PATHS[@]}"; do
        eval "path_expanded=$path"
        [[ -d "$path_expanded" ]] && PATH="$PATH:$path_expanded"
    done

    # Set environment variables
    for var in "${ENV_VARS[@]}"; do
        export "$var"
    done

    log_info "Environment configured successfully"
}

setup_completion() {
    log_info "Setting up completion..."
    if ! shopt -oq posix; then
        if [ -f /usr/share/bash-completion/bash_completion ]; then
            . /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
            . /etc/bash_completion
        fi
    fi
    log_info "Completion setup complete"
}
