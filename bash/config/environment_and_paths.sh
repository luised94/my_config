#!/bin/bash
# =============================================================
# Consolidated Environment and PATH Settings Configuration File
# =============================================================
#
# This file contains the consolidated configuration for both
# environment variables and additional PATH settings.
# It is intended to be sourced (e.g., from your init.sh) to set up
# your development environment.
#
# References:
# - Bash PATH best practices [1]
# - How to set environment variables permanently [5]
# - Processing modular configuration files [12]
# =============================================================

##############################
# Section: Environment Vars  #
##############################

# Define environment variables in key=value string format.
declare -a ENV_VARS=(
  "GIT_EDITOR=nvim"
  "R_HOME=/usr/local/bin/R"
  "R_LIBS_USER=~/R/library/"
  "BROWSER=/mnt/c/Program Files (x86)/BraveSoftware/Brave-Browser/Application/brave.exe"
  "MANPAGER=nvim +Man!"
)

# Export each of the environment variables.
for env in "${ENV_VARS[@]}"; do
  export "$env"
done

################################
# Section: Additional PATH     #
################################

# Define additional directories to add to the PATH.
declare -a ADDITIONAL_PATHS=(
  "~/node-v22.5.1-linux-x64/bin"
)

# Iterate over each additional path.
for p in "${ADDITIONAL_PATHS[@]}"; do
    # Expand '~' to the full home directory path.
    expanded_path="${p/#\~/$HOME}"
    # Check if the directory exists.
    if [ -d "$expanded_path" ]; then
        # Append the directory if it is not already in PATH.
        case ":$PATH:" in
            *":$expanded_path:"*) ;;  # Already in PATH.
            *) PATH="$PATH:$expanded_path";;
        esac
    fi
done

# Export the updated PATH variable.
export PATH

# Uncomment the next line for debugging purposes:
# echo "Current PATH: $PATH"
