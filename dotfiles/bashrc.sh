# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
  *i*) ;;
    *) return;;
esac
# @QUES: Should I add basic checks for assumed programs in my bashrc?
# Set vi mode
set -o vi

# Base directory detection
#readonly BASH_UTILS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASH_UTILS_ROOT="$HOME/personal_repos/my_config/bash/"
if [ ! -d "$BASH_UTILS_ROOT" ]; then
  printf "[WARNING] BASH_UTILS_ROOT dir does not exist.\n"
  printf "Current setting: %s\n" "$BASH_UTILS_ROOT"

fi

# Verify that programs used throughout scripts and configuration are available 
REQUIRED_PROGRAMS=(
  "git"
  "tmux"
  "nvim"
  "fzf"
)

for program in "${REQUIRED_PROGRAMS[@]}"; do
  if ! command -v "$program" >/dev/null 2>&1; then
    printf 'WARNING: %s program is not available. Some scripts or functions may not work.\n' "${program}" >&2

  fi

done

# Logging setup
if [[ -z "$LOG_LEVEL" ]]; then
  export LOG_LEVEL="INFO"

fi

# Function files
# Missing file (typo or deletion) should output [ERROR] Required function file not found:
FUNCTION_FILES=(
  "logging_utils.sh"
  "file_operations.sh"
  "view_files_in_browser.sh"
  "git_automations.sh"
  "directory_tree.sh"
)

# Load function files
for func in "${FUNCTION_FILES[@]}"; do
  if [[ -f "${BASH_UTILS_ROOT}/functions/${func}" ]]; then
    source "${BASH_UTILS_ROOT}/functions/${func}"
  else
    printf "[ERROR] Required function file not found: %s\n" "${func}"
    return 1
  fi

done

log_info "Bash utilities initialized successfully"
#[[ -z "$_BASH_UTILS_INITIALIZED" ]] && source "$BASH_UTILS_PATH/init.sh"

# History settings
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

# Shell options
SHELL_OPTIONS=(
  "histappend"
  "checkwinsize"
)

# Color support
COLOR_SUPPORT=1
GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Apply shell options from configuration
for opt in "${SHELL_OPTIONS[@]}"; do
  shopt -s "$opt"
done

# Set up prompt
log_info "Configuring shell prompt..."

PS1='\u@\h:\w\$ '

log_info "Prompt configuration complete..."

# Set up aliases
# Defined in aliases_config and source in init.sh
log_info "Setting up aliases..."
MY_SHELL_ALIASES=(
  # --- Basic aliases ---
  "l=ls -CF"
  "la=ls -A"
  "ll=ls -alF"
  # --- Programming language aliases ---
  "R=R --no-save"

  # --- WSL/WINDOWS related ---
  "cdwin=cd \"\$DROPBOX_PATH\"" # Escape the quotes and the $ to prevent expansion and quote when evaluated
  "explorer=explorer.exe ."

  # --- Git aliases ---
  "ga=git add"
  "gb=git branch"
  "gc=git commit"
  "gcb=git checkout -b"
  "gco=git checkout"
  "gd=git diff"
  "gfap=git fetch --all --prune"
  "gl=git log --oneline --graph --decorate"
  "gm=git merge"
  "gmnff=git merge --no-ff"
  "gpl=git pull"
  "gps=git push"
  "grm=git rebase main"
  "gs=git status"
  "ngd=nvim < <(git diff)"
  "ngda=nvim < <(git diff HEAD)"
  "ngdc=nvim < <(git diff --cached)"
  "nglc=git diff-tree --no-commit-id --name-only -r -z HEAD | xargs -0 nvim"
  #"gitstart=git fetch --all --prune && git status && git pull && git rebase main && echo [X] Git workspace ready for coding!'"
  #"syncall=sync_all_branches"

  # --- Script aliases ---
  "setup_tmux=~/personal_repos/my_config/scripts/tmux_setup_worktree_sessions.sh"

  # --- Lab utils aliases ---
  "edit_bmc_configs=nvim ~/data/*Bel/documentation/*_bmc_config.R ~/personal_repos/lab_utils/core_scripts/template_configuration_experiment_bmc.R ~/personal_repos/lab_utils/core_scripts/template_configuration_experiment_bmc.R"
)

for alias_def in "${MY_SHELL_ALIASES[@]}"; do
  #echo "${alias_def}"
  alias "${alias_def}"
done

# Alert alias for long running commands
#alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

log_info "Aliases configured successfully"

# Set up environment variables and paths
log_info "Setting up environment..."
# Path configurations
ADDITIONAL_PATHS=(
    #"~/node-v22.5.1-linux-x64/bin"
    "/opt/zig"
)
# Add additional paths
for path in "${ADDITIONAL_PATHS[@]}"; do
    eval "path_expanded=$path"
    [[ -d "$path_expanded" ]] && PATH="$PATH:$path_expanded"
done

# Environment variables
ENV_VARS=(
  "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
  "GIT_EDITOR=nvim"
  "MANPAGER=nvim +Man!"
  "R_HOME=/usr/local/bin/R"
  "R_LIBS_USER=/opt/R/library/"
)

# Set environment variables
for var in "${ENV_VARS[@]}"; do
  export "$var"
done

log_info "Environment variables configured..."


# Set up Windows environment if in WSL
if [[ -n "$WSL_DISTRO_NAME" ]]; then
  #setup_windows_environment
    windows_user=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    if [[ -z "$windows_user" ]]; then
      log_error "Error: Unable to retrieve Windows username." >&2
      return 1
    fi
    # Set up Dropbox path
    #dropbox_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)/"
    dropbox_path="/mnt/c/Users/${windows_user}/MIT Dropbox/Luis Martinez"

    log_info "Windows User: $windows_user"
    log_info "Dropbox path: $dropbox_path"

    if [[ ! -d "$dropbox_path" ]]; then

      log_warning "Warning: Dropbox directory not found at $dropbox_path" >&2
      # Attempt to find Dropbox directory
      potential_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)"
      if [[ -d "$potential_path" ]]; then

        dropbox_path="$potential_path/"
        log_info "Found Dropbox at $dropbox_path" >&2

      else

        log_error "Error: Unable to locate Dropbox directory." >&2
        return 1

      fi

    fi

    # Export variables
    export WINDOWS_USER="$windows_user"
    export DROPBOX_PATH="$dropbox_path"

    log_info "Dropbox path setup complete..."
fi

# Enable programmable completion
log_info "Setting up completion..."
if ! shopt -oq posix; then

    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi

fi
log_info "Completion setup complete..."

# Change to home directory
#cd ~ || echo "Error changing to home directory"

# Additional environment-specific settings
if [ -x /usr/bin/lesspipe ]; then
  eval "$(SHELL=/bin/sh lesspipe)"
fi

# Set up chroot
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
  debian_chroot=$(cat /etc/debian_chroot)
fi

# Source additional local configurations if they exist
if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

if [ -f ~/.bash_local ]; then
  . ~/.bash_local
fi

# Load custom completions
if [ -d ~/.bash_completion.d ]; then
  for file in ~/.bash_completion.d/*; do
    [ -f "$file" ] && . "$file"
  done
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# TODO: Add to configuration script or something
export ODIN_ROOT="$HOME/Odin"
export PATH="$ODIN_ROOT:$PATH"
#eval $(opam env)
#. "/home/lius/.deno/env"

# Switch to home directory if not in Tmux
if [ -z "$TMUX" ]; then
  cd "$HOME"

fi

# End
log_info "Shell initialization complete..."
