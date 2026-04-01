-- ftplugin/hledger.lua - buffer-local settings for hledger journals

vim.opt_local.expandtab = true
vim.opt_local.tabstop = 2
vim.opt_local.shiftwidth = 2
vim.opt_local.textwidth = 0
vim.opt_local.formatoptions:remove("t")

vim.b.ts_highlight = false
-- === Syntax Highlighting ===

vim.cmd([[
  syntax match hledgerDate       "^\d\{4\}-\d\{2\}-\d\{2\}"
  syntax match hledgerAccount    "\s\+[a-zA-Z][a-zA-Z0-9_-]*\(:[a-zA-Z0-9_-]\+\)\+"
  syntax match hledgerAmount     "\$-\?\d\+\(\,\d\{3\}\)*\(\.\d\+\)\?"
  syntax match hledgerCleared    "^\d\{4\}-\d\{2\}-\d\{2\}\s\+\zs\*"
  syntax match hledgerPending    "^\d\{4\}-\d\{2\}-\d\{2\}\s\+\zs!"
  syntax match hledgerComment    "^;.*$"
  syntax match hledgerInlineComment "\s;.*$"

  highlight link hledgerDate        Constant
  highlight link hledgerAccount     Identifier
  highlight link hledgerAmount      Number
  highlight link hledgerCleared     Type
  highlight link hledgerPending     Todo
  highlight link hledgerComment     Comment
  highlight link hledgerInlineComment Comment
]])
