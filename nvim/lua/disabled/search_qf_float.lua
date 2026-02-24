-- Disabled: floating quickfix window for SearchQF
-- To re-enable: move create_floating_window into the UTILITIES section of init.lua
-- and wire it into search_and_show when floating == true
-- Depends on: SEARCH_QF_CONFIG.window (width, height, padding, blend)
---@class SearchQFWindow
---@field width   integer
---@field height  integer
---@field padding integer
---@field blend   integer

---@class SearchQFConfig
---@field window SearchQFWindow

---@type SearchQFConfig
local SEARCH_QF_CONFIG = {
    window = {
        width   = 80,
        height  = 20,
        padding = 2,
        blend   = 10,
    },
}

---@param config SearchQFConfig
---@return integer, integer
local function create_floating_window(config)
    local opts = {
        relative = 'editor',
        width    = config.window.width,
        height   = config.window.height,
        row      = config.window.padding,
        col      = config.window.padding,
        border   = 'rounded',
        style    = 'minimal',
    }
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, opts)
    local qflist = vim.fn.getqflist()
    if #qflist > 0 then
        local lines = vim.tbl_map(function(item) return item.text or "" end, qflist)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "No matches found" })
    end
    vim.wo[win].winbl = config.window.blend
    return buf, win
end

return { create_floating_window = create_floating_window }
