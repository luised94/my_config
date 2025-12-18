# ~/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
case $- in
  *i*) ;;
    *) return;;
esac
set -o vi # Set vi mode

if [[ -n "$TMUX" ]]; then
  _session=$(tmux display-message -p '#S')

  if [[ "$_session" == my_config\>* ]]; then
    _branch=${_session#my_config>}
    BASH_UTILS_ROOT="$HOME/personal_repos/my_config-${_branch}/bash"

  fi

  unset _session _branch

fi

BASH_UTILS_ROOT="${BASH_UTILS_ROOT:-$HOME/personal_repos/my_config/bash}"
#BASH_UTILS_ROOT="$HOME/personal_repos/my_config-vim_all_in_R/bash/"

DEFAULT_EDITORS=(
    "nvim"
    "vim"
)

REQUIRED_PROGRAMS=(
  "git"
  "tmux"
  "nvim"
  "fzf"
)

FUNCTION_FILES=(
  "logging_utils.sh"
  "file_operations.sh"
  "vim_helpers.sh"
  "view_files_in_browser.sh"
  "git_automations.sh"
  "directory_tree.sh"
)

# Path configurations
ADDITIONAL_PATHS=(
    #"~/node-v22.5.1-linux-x64/bin"
    "/opt/zig"
)

# Environment variables
ENV_VARS=(
  "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
  "GIT_EDITOR=nvim"
  "MANPAGER=nvim +Man!"
  "R_HOME=/usr/local/bin/R"
  "R_LIBS_USER=/opt/R/library/"
)

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
  # Needs to be turned into a project specific config.
  "edit_bmc_configs=nvim ~/data/*Bel/documentation/*_bmc_config.R ~/personal_repos/lab_utils/core_scripts/template_configuration_experiment_bmc.R ~/personal_repos/lab_utils/core_scripts/template_configuration_experiment_bmc.R"
)

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

PS1='\u@\h:\w\$ '

if [ ! -d "$BASH_UTILS_ROOT" ]; then
  printf "[WARNING] BASH_UTILS_ROOT dir does not exist.\n"
  printf "Current setting: %s\n" "$BASH_UTILS_ROOT"
  printf "Clone git repository."

fi

# Verify that programs used throughout scripts and configuration are available 
for program in "${REQUIRED_PROGRAMS[@]}"; do
  if ! command -v "$program" >/dev/null 2>&1; then
    printf 'WARNING: %s program is not available. Some scripts or functions may not work.\n' "${program}" >&2

  fi

done

for editor in "${DEFAULT_EDITORS[@]}"; do
  if command -v "$editor" >/dev/null 2>&1; then
    EDITOR="$editor"
    break

  fi

done

if [[ -z $EDITOR ]]; then
  printf "[ERROR] No suitable editors found."

fi

# Logging setup
if [[ -z "$LOG_LEVEL" ]]; then
  export LOG_LEVEL="INFO"

fi

# Function files
# Load function files
for func in "${FUNCTION_FILES[@]}"; do
  if [[ ! -f "${BASH_UTILS_ROOT}/functions/${func}" ]]; then
    printf "[ERROR] Required function file not found: %s\n" "${func}" >&2
    continue

  fi

  if ! source "${BASH_UTILS_ROOT}/functions/${func}"; then
    printf "[ERROR] Failed to source %s (exit code: %s)" "${func}" "$?" >&2
    continue

  fi

done

for opt in "${SHELL_OPTIONS[@]}"; do
  shopt -s "$opt"
done

for alias_def in "${MY_SHELL_ALIASES[@]}"; do
  #echo "${alias_def}"
  alias "${alias_def}"
done

# Set up environment variables and paths
# Add additional paths
for path in "${ADDITIONAL_PATHS[@]}"; do
    eval "path_expanded=$path"
    [[ -d "$path_expanded" ]] && PATH="$PATH:$path_expanded"

done

# Set environment variables
for var in "${ENV_VARS[@]}"; do
  export "$var"
done

# Set up Windows environment if in WSL
if [[ -n "$WSL_DISTRO_NAME" ]]; then
  #setup_windows_environment
    windows_user=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    if [[ -z "$windows_user" ]]; then
      log_error "Error: Unable to retrieve Windows username." >&2
    fi
    # Set up Dropbox path
    #dropbox_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)/"
    dropbox_path="/mnt/c/Users/${windows_user}/MIT Dropbox/Luis Martinez"

    #log_info "Windows User: $windows_user"
    #log_info "Dropbox path: $dropbox_path"

    if [[ ! -d "$dropbox_path" ]]; then

      log_warning "Warning: Dropbox directory not found at $dropbox_path" >&2
      # Attempt to find Dropbox directory
      potential_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)"
      if [[ -d "$potential_path" ]]; then

        dropbox_path="$potential_path/"
        log_info "Found Dropbox at $dropbox_path" >&2

      else

        log_error "Error: Unable to locate Dropbox directory." >&2

      fi

    fi

    # Export variables
    export WINDOWS_USER="$windows_user"
    export DROPBOX_PATH="$dropbox_path"

    #log_info "Dropbox path setup complete..."
fi

# Enable programmable completion
#log_info "Setting up completion..."
if ! shopt -oq posix; then

    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi

fi

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

# Change to home directory
#cd ~ || echo "Error changing to home directory"

# End
log_info "Shell initialization complete..."

# Alert alias for long running commands
#alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
# Base directory detection
#readonly BASH_UTILS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
