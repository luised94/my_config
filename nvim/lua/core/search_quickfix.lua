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

-- Save and restore user location
local function save_user_location()
    return {
        winnr = vim.api.nvim_get_current_win(),
        buffer = vim.api.nvim_get_current_buf(),
        cursor = vim.api.nvim_win_get_cursor(0),
    }
end

local function restore_user_location(location)
    if not location or not location.buffer or not location.cursor then return end

    -- Check if buffer is valid
    if not vim.api.nvim_buf_is_valid(location.buffer) then return end

    -- Check if window is valid
    if vim.api.nvim_win_is_valid(location.winnr) then
        vim.api.nvim_set_current_win(location.winnr)
    end

    -- Check if cursor position is within bounds
    local line_count = vim.api.nvim_buf_line_count(location.buffer)
    local cursor_line = math.min(location.cursor[1], line_count)
    local cursor_col = math.min(location.cursor[2], #vim.api.nvim_buf_get_lines(location.buffer, cursor_line - 1, cursor_line, false)[1] or 0)

    -- Restore buffer and cursor position
    vim.api.nvim_set_current_buf(location.buffer)
    vim.api.nvim_win_set_cursor(0, {cursor_line, cursor_col})
end

local function search_buffers(search_string)
    reset_quickfix_list()
    vim.cmd(string.format([[
        silent! bufdo if filereadable(expand('%%:p')) | vimgrepadd /%s/ %% | endif
    ]], vim.fn.escape(search_string, '/')))
end



-- Floating window functionality (commented out for now)
--[[
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
]]

local function is_quickfix_open()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buf_type = vim.bo[buf].buftype
        if buf_type == 'quickfix' then
            return true, win
        end
    end
    return false, nil
end

local function close_quickfix_if_empty()
    local qf_list = vim.fn.getqflist({ size = 0 })
    if qf_list.size == 0 then
        local qf_open, qf_win = is_quickfix_open()
        if qf_open and qf_win then
            -- Check if quickfix is the only window
            if #vim.api.nvim_tabpage_list_wins(0) == 1 then
                -- Move to the first valid buffer before closing
                for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == '' then
                        vim.api.nvim_set_current_buf(buf)
                        break
                    end
                end
            end
            -- Close the quickfix window
            vim.cmd('cclose')
        end
    end
end


function M.search_and_show(search_string, floating)
    if not validate_search(search_string) then return end

    -- Save user location before running the search
    local user_location = save_user_location()

    local ok, result = pcall(function()
        search_buffers(search_string)

        if vim.fn.getqflist({size = 0}).size == 0 then
            restore_user_location(user_location)
            vim.notify("No matches found for: " .. search_string, vim.log.levels.WARN)
            close_quickfix_if_empty()
            return
        end

        if floating then
            vim.notify("Floating window is currently disabled", vim.log.levels.INFO)
            restore_user_location(user_location)
        else
            -- Check if quickfix is already open
            local qf_open, qf_win = is_quickfix_open()
            if qf_open and qf_win and vim.api.nvim_win_is_valid(qf_win) then
                -- If quickfix is open and valid, just refresh it
                local current_win = vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(qf_win)
                vim.cmd('cbottom') -- Move to bottom of quickfix list
                vim.api.nvim_set_current_win(current_win)
            else
                -- Open new quickfix window
                vim.cmd('botright copen')
            end

            -- Return to the original window after opening/refreshing quickfix list
            restore_user_location(user_location)
        end

        -- Close quickfix if empty (e.g., after filtering results manually)
        close_quickfix_if_empty()
    end)

    if not ok then
        restore_user_location(user_location)
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
