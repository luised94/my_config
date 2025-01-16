-- core/search_quickfix.lua
local M = {}

M.config = {
    window = {
        width = 80,
        height = 20,
        padding = 2,
        blend = 10
    }
}

local function validate_search(search_string)
    if not search_string or search_string == "" then
        vim.notify("Search string cannot be empty", vim.log.levels.ERROR)
        return false
    end
    return true
end

local function reset_quickfix_list()
    vim.cmd("silent! call setqflist([])")
end
local function search_buffers(search_string)
    reset_quickfix_list()
    vim.cmd(string.format([[
        silent! bufdo if filereadable(expand('%%:p')) | vimgrepadd /%s/ %% | endif
    ]], vim.fn.escape(search_string, '/')))
end


-- Floating window functionality (commented out for now)
local function create_floating_window()
    local opts = {
        relative = 'editor',
        width = M.config.window.width,
        height = M.config.window.height,
        row = M.config.window.padding,
        col = M.config.window.padding,
        border = 'rounded',
        style = 'minimal'
    }
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, opts)

    -- Populate the buffer with quickfix list content
    local qflist = vim.fn.getqflist()
    if #qflist > 0 then
        local lines = {}
        for _, item in ipairs(qflist) do
            table.insert(lines, item.text or "")
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"No matches found"})
    end

    -- Set options for the floating window
    vim.wo[win].winbl = M.config.window.blend

    return buf, win
end

function M.search_and_show(search_string, floating)
    if not validate_search(search_string) then return end
    
    local ok, result = pcall(function()
        vim.cmd('silent! cclose')
        search_buffers(search_string)
        
        if vim.fn.getqflist({size = 0}).size == 0 then
            vim.notify("No matches found for: " .. search_string, vim.log.levels.WARN)
            return
        end

        if floating then
            -- Uncomment below to enable floating window functionality later
             local buf, win = create_floating_window()
             vim.cmd('copen')
             vim.cmd('wincmd P')
            vim.notify("Floating window is currently disabled", vim.log.levels.INFO)
        else
            vim.cmd('copen')
        end
    end)

    if not ok then
        vim.notify("Search failed: " .. tostring(result), vim.log.levels.ERROR)
    end
end

-- Create commands
vim.api.nvim_create_user_command('SearchQF', function(opts)
    local args = opts.fargs
    local floating = false
    local search_term = ""

    if #args > 0 then
        if args[1] == "float" then
            floating = true
            search_term = table.concat(args, " ", 2)
        else
            search_term = table.concat(args, " ")
        end
    end

    M.search_and_show(search_term, floating)
end, {
    nargs = "+",
    complete = function(_, _, _)  -- Ignore unused parameters
        return {"float"}
    end
})

--[[ To add Which-key integration later, add this to your which-key.lua:

require("which-key").register({
    ["<leader>s"] = {
        name = "Search",
        q = { "<cmd>SearchQF ", "Search in Quickfix" },
        f = { "<cmd>SearchQF float ", "Search in Float Window" },
    }
})

Or add these direct keymaps to your keymaps.lua:

vim.keymap.set('n', '<leader>sq', ':SearchQF ', { desc = "Search in Quickfix" })
vim.keymap.set('n', '<leader>sf', ':SearchQF float ', { desc = "Search in Float Window" })
--]]

return M
