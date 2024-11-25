#!/bin/bash
# System information
echo "=== System Information ==="
echo "OS: $(uname -a)"
echo -e "\n=== Shell Information ==="
echo "Shell: $SHELL version $(bash --version | head -n1)"

# Neovim information
echo -e "\n=== Neovim Information ==="
nvim --version | head -n1
echo "Neovim config location: ${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# R version and library path
echo -e "\n=== R Information ==="
R --version | head -n1
R -e '.libPaths()'

# Directory structure
echo "Home directory structure:"
tree -L 2 ~/ | head -n 10

# Current dotfiles
ls -la ~/.* | grep -E "bashrc|vimrc|config"

# List Neovim plugins
echo "=== Neovim Plugins ==="
ls -la "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/plugins"
nvim --headless -c "lua print(vim.inspect(vim.fn.getcompletion('', 'packadd')))" -c q

# List current automation scripts
echo -e "\n=== Automation Scripts ==="
find ~/my_config/ -name "*.sh" -o -name "*.R" -o -name "*.lua" | grep -v "/\."

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
for cmd in dropbox rclone rsync; do
    which $cmd >/dev/null && echo "$cmd: available" || echo "$cmd: not found"
done
