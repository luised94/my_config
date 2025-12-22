
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

# --- Color Codes ---
if [[ -t 2 ]] && command -v tput &>/dev/null && [[ $(tput colors) -ge 8 ]]; then
    _COLOR_RESET='\033[0m'
    _COLOR_ERROR='\033[0;31m'
    _COLOR_WARN='\033[0;33m'
    _COLOR_INFO='\033[0;36m'
    _COLOR_DEBUG='\033[0;90m'

else
    _COLOR_RESET=''
    _COLOR_ERROR=''
    _COLOR_WARN=''
    _COLOR_INFO=''
    _COLOR_DEBUG=''

fi

# ============================================================================
# File and directory exclusions for vim helper functions
# These can be overridden by defining these arrays before sourcing this file
# ============================================================================
# Default exclusion directories (if not already defined)
if [[ ${#MC_EXCLUDE_DIRS[@]} -eq 0 ]]; then
    MC_EXCLUDE_DIRS=(
        # Version control
        ".git"

        # Node/JavaScript ecosystem
        "node_modules"
        ".next"
        ".nuxt"
        ".svelte-kit"

        # Python ecosystem
        "__pycache__"
        ".venv"
        "venv"
        "env"
        ".pytest_cache"
        ".mypy_cache"
        ".tox"
        ".ipynb_checkpoints"

        # R ecosystem
        "renv"
        ".Rproj.user"

        # Build artifacts (multi-language)
        "build"
        "dist"
        "target"
        "out"
        "bin"

        # Dependencies/vendors
        "vendor"
        "deps"

        # IDE/Editor
        ".idea"
        ".vscode"

        # Cache/temp
        ".cache"
        "tmp"
        "temp"

        # Coverage/test reports
        "coverage"
        "htmlcov"
    )

fi

# Default exclusion file patterns (if not already defined)
if [[ ${#MC_EXCLUDE_FILES[@]} -eq 0 ]]; then
    MC_EXCLUDE_FILES=(
        # Logs and temp files
        "*.log"
        "*.tmp"
        "*.bak"
        "*.swp"
        "*.swo"

        # Compiled/bytecode
        "*.pyc"
        "*.pyo"
        "*.o"
        "*.so"
        "*.a"
        "*.class"

        # OS files
        ".DS_Store"
        "Thumbs.db"

        # Your custom exclusions
        "*repository_aggregate.md"
        "*.gitignore"
        "*.Rprofile"
        "*renv.lock"
    )

fi
