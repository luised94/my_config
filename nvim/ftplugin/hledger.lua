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
-- === Account Abbreviations ===

local abbrevs = {
    { "chk",   "assets:checking" },
    { "sav",   "assets:savings" },
    { "cah",   "assets:cash" },
    { "oc",    "liabilities:cards:oriental_checking" },
    { "sal",   "income:salary" },
    { "iint",  "income:interest" },
    { "ioth",  "income:other" },
    { "rent",  "expenses:housing:rent" },
    { "elec",  "expenses:utilities:electric" },
    { "inet",  "expenses:utilities:internet" },
    { "phon",  "expenses:utilities:phone" },
    { "groc",  "expenses:food:groceries" },
    { "din",   "expenses:food:dining" },
    { "fuel",  "expenses:transport:fuel" },
    { "tran",  "expenses:transport:transit" },
    { "ride",  "expenses:transport:rideshare" },
    { "hins",  "expenses:health:insurance" },
    { "hmed",  "expenses:health:medical" },
    { "hphm",  "expenses:health:pharmacy" },
    { "pers",  "expenses:personal" },
    { "ent",   "expenses:entertainment" },
    { "subs",  "expenses:subscriptions" },
    { "shop",  "expenses:shopping" },
    { "trav",  "expenses:travel" },
    { "gift",  "expenses:gifts" },
    { "fees",  "expenses:fees" },
    { "eqob",  "equity:opening-balances" },
}

for _, ab in ipairs(abbrevs) do
    vim.cmd(string.format("iabbrev <buffer> %s %s", ab[1], ab[2]))
end
