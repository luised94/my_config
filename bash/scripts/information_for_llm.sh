#!/bin/bash
# System information
echo -e "\n=== System Information ==="
echo "OS: $(uname -a)"
echo -e "\n=== Shell Information ==="
echo "Shell: $SHELL version $(bash --version | head -n1)"

# Neovim information
echo -e "\n=== Neovim Information ==="
nvim --version | head -n1
echo "Neovim config location: ${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# R version and library path with Warning Suppression
echo -e "\n=== R Information ==="
TMP=$R_HOME
{
    # Temporarily unset problematic environment variables
    unset R_HOME
    
    # Capture R version quietly
    R_VERSION=$(R --version 2>/dev/null | grep "^R version" | head -n1)
    echo "$R_VERSION"
    
    # Original R library paths command
    R -e '.libPaths()' | grep "\["
}
R_HOME=$TMP

# Python version
echo -e "\n=== Python Information ==="
python3 --version
#
# Python Package Management
echo "Python Package Managers:"
which pip3 >/dev/null && pip3 --version
which conda >/dev/null && conda --version

# Python Package Count
echo "Installed Python Packages:"
pip3 list | wc -l

# Python Virtual Environment
echo "Active Virtual Environment:"
[[ -n "$VIRTUAL_ENV" ]] && basename "$VIRTUAL_ENV" || echo "No active venv"

# Python Paths
echo "Python Executable Path: $(which python3)"
echo "Python Library Paths:"
python3 -c "import sys; print('\n'.join(sys.path))" | head -n 5

# Node.js Information
echo -e "\n=== Node.js Information ==="
node --version

# Node Package Management
echo "Package Managers:"
which npm >/dev/null && npm --version

which yarn >/dev/null && yarn --version

# Global vs Local Packages
echo "Global NPM Packages:"
npm list -g --depth=0 | wc -l

echo "Local Project Packages:"
[[ -f package.json ]] && npm list --depth=0 | wc -l || echo "No local project detected"

# Node.js Runtime Environment
echo "Node.js Executable Path: $(which node)"

# Directory structure
echo "Home directory structure:"
tree -L 2 ~/ | head -n 10

# Current dotfiles
ls -la ~/.* | grep -E "bashrc|vimrc|config"

# List Neovim plugins
echo "=== Neovim Plugins ==="
lazy_plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
if [[ -d "$lazy_plugin_dir" ]]; then
    echo "Lazy.nvim plugin directory: $lazy_plugin_dir"
    ls -1 "$lazy_plugin_dir"
else
    echo "Lazy.nvim plugin directory not found"
fi

#ls -la "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/plugins"
nvim --headless -c "lua print(vim.inspect(vim.fn.getcompletion('', 'packadd')))" -c q

# List current automation scripts
echo -e "\n=== Automation Scripts ==="
find ~/my_config/ -name "*.sh" -o -name "*.R" -o -name "*.lua" -o -name "*.js" | grep -v "/\."

# Check common tool availability
echo -e "\n=== Tool Availability ==="
for cmd in fzf rg fd bat git; do
    which $cmd >/dev/null && echo "$cmd: $(which $cmd)" || echo "$cmd: not found"
done

# Storage information
echo -e "\n=== Storage Information ==="
df -h ~
echo "Backup devices:"
lsblk

# Cloud sync availability
echo -e "\n=== Cloud Sync Information ==="
for cmd in dropbox rclone rsync; do
    which $cmd >/dev/null && echo "$cmd: available" || echo "$cmd: not found"
done
