# Shell configuration settings
# Do not source directly - use init.sh

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

# Environment variables
ENV_VARS=(
    "GIT_EDITOR=nvim"
    "R_HOME=/usr/local/bin/R"
    "R_LIBS_USER=~/R/library/"
    "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
    "MANPAGER=nvim +Man!"
)

# Additional paths
ADDITIONAL_PATHS=(
    "~/node-v22.5.1-linux-x64/bin"
    "/opt/zig"
)
