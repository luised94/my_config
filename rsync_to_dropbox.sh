#!/bin/bash
# This is found on bashrc file and should be already. Check by echoing variable. 
# windows_user=$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r')
# windows_path="/mnt/c/Users/${windows_user}/Dropbox (MIT)/"
rsync -av ~/my_config/ "${windows_path}my_config/"
#find ~/.config/ -type d -name "*nvim*" ! -name "*.bak*" -exec rsync -av {} "${windows_path}neovim/" \;
# Rsync to dropbox for backup to external hard drive
#rsync -av --no-perms --no-owner --no-group --no-times --delete "/mnt/c/Users/liusm/Dropbox (MIT)/zotero-storage" "/mnt/d/"
