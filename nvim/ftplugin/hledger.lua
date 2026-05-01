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
-- When adding new accounts to the journal, add a corresponding
-- abbreviation here. Run :iabbrev in a journal buffer to list
-- all active abbreviations.
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
-- === Report Keybindings ===
local function open_hledger_report(cmd)
    local output = vim.fn.system(cmd)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n"))
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, buf)
end
vim.keymap.set("n", "<leader>b", function()
    open_hledger_report("hledger bal")
end, { buffer = true, desc = "hledger: balance report" })
vim.keymap.set("n", "<leader>i", function()
    open_hledger_report("hledger is")
end, { buffer = true, desc = "hledger: income statement" })
vim.keymap.set("n", "<leader>f", function()
    local dir = vim.env.FINANCES_DIR
    if not dir then
        vim.notify("FINANCES_DIR not set", vim.log.levels.WARN)
        return
    end
    require("telescope.builtin").live_grep({ cwd = dir })
end, { buffer = true, desc = "hledger: search finances directory" })
