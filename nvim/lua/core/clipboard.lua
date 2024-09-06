-- This is required in addition to vim.opt.clipboard option.
if vim.fn.has('wsl') == 1 then
        vim.g.clipboard = {
                name = 'WslClipboard',
                copy = {
                        ['+'] = 'clip.exe',
                        ['*'] = 'clip.exe',
                    },
                paste = {
                        ['+'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
                        ['*'] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
                    },
                cache_enabled = 0,
            }
end
-- second alternative.
--#!/bin/bash
--    case "$1" in
--      -o)
--    powershell.exe Get-Clipboard | sed 's/\r$//' | sed -z '$ s/\n$//'
--    ;;
--  -i)
--    tee <&0 | clip.exe
--    ;;
--esac
--Make it executable and place in chmod +x /usr/local/bin/xsel. export DISPLAY=:0
