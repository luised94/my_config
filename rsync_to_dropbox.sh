#!/bin/bash
# This is found on bashrc file and should be already. Check by echoing variable. 
# windows_user=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
# windows_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)/"
rsync -av ~/dotfiles/ "${windows_path}dotfiles/"
find ~/.config/ -type d -name "*nvim*" ! -name "*.bak*" -exec rsync -av {} "${windows_path}neovim/" \;
