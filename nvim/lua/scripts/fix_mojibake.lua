-- fix_mojibake.lua
-- Usage (recommended):
--   1) Open llm.py
--   2) :e fix_mojibake.lua
--   3) :luafile %
--   4) Go back to llm.py and :w
local function esc_lua_pattern(s)
  -- Escape Lua pattern metacharacters so gsub matches literal text.
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end
-- Pick the target buffer:
-- - If you run :luafile % from this Lua file, the "alternate" buffer (#) is usually your llm.py.
-- - If there's no alternate buffer, it falls back to the current buffer.
local cur = vim.api.nvim_get_current_buf()
local alt = vim.fn.bufnr("#")
local target = (alt > 0 and alt ~= cur and vim.api.nvim_buf_is_loaded(alt)) and alt or cur
-- Edit these mappings as needed.
local replacements = {
  ["¯"] = ">>",
  ["®"] = "<<",
  ["Ä"] = "-",
  ["³"] = "|",
  ["ú"] = "->",
}
local lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
local changed_lines = 0
local total_replacements = 0
for i, line in ipairs(lines) do
  local new = line
  for bad, good in pairs(replacements) do
    local n
    new, n = new:gsub(esc_lua_pattern(bad), good)
    total_replacements = total_replacements + n
  end
  if new ~= line then
    lines[i] = new
    changed_lines = changed_lines + 1
  end
end
vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
-- Ensure the target buffer will be written as UTF-8.
vim.bo[target].fileencoding = "utf-8"
local name = vim.api.nvim_buf_get_name(target)
if name == "" then name = ("[buf %d]"):format(target) end
vim.notify(
  ("Mojibake fix applied to %s: %d replacements across %d lines")
    :format(name, total_replacements, changed_lines),
  vim.log.levels.INFO
)
