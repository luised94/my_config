# ------------------------------------------------------------------------------
# TITLE      : MC Activation Engine (01_activate.sh)
# PURPOSE    : Processes and applies configuration arrays defined in 00_mc_config.sh.
# CONTEXT    : Sourced by .bashrc as part of the MC Framework initialization.
# DEPENDS    : 00_mc_config.sh (Must be sourced first)
# USAGE      : source "$MC_ROOT/core/01_activate.sh"
# DATE       : 2025-12-22
# ------------------------------------------------------------------------------

# Apply Shell Options (shopt)
for opt in "${MC_SHELL_OPTIONS[@]}"; do
    shopt -s "$opt" 2>/dev/null
done

# Apply Aliases
for alias_def in "${MC_ALIASES[@]}"; do
    alias "$alias_def"
done

# Apply Environment Variables
for var in "${MC_ENV_VARS[@]}"; do
    export "$var"
done

# Expand and Apply PATHs
for p in "${MC_ADDITIONAL_PATHS[@]}"; do
    eval "p_expanded=$p"
    [[ -d "$p_expanded" ]] && PATH="$PATH:$p_expanded"
done

# Set the default editor.
for editor in "${MC_DEFAULT_EDITORS[@]}"; do
  if command -v "$editor" >/dev/null 2>&1; then
    EDITOR="$editor"
    break

  fi

done

# Allow less to open compressed files as text.
[[ -x /usr/bin/lesspipe ]] && eval "$(SHELL=/bin/sh lesspipe)"

# Setup completions
if ! shopt -oq posix; then
    if [[ -f /usr/share/bash-completion/bash_completion ]]; then
        source /usr/share/bash-completion/bash_completion
    elif [[ -f /etc/bash_completion ]]; then
        source /etc/bash_completion
    fi
fi

# Also include your custom completions loop here
if [[ -d ~/.bash_completion.d ]]; then
    for _comp_file in ~/.bash_completion.d/*; do
        [[ -f "$_comp_file" ]] && source "$_comp_file"
    done
    unset _comp_file
fi

# Apply Individual Preferences
export PATH
export EDITOR
export HISTCONTROL="$MC_HISTCONTROL"
export HISTSIZE="$MC_HISTSIZE"
export HISTFILESIZE="$MC_HISTFILESIZE"
export PS1="$MC_PS1"

# Final Verification Call (The Caching Strategy we discussed)
# This ensures that even after activating, we double-check everything works.
if [[ $(type -t mc_verify_system) == "function" ]]; then
    mc_verify_system
fi
