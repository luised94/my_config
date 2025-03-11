
local DEFAULT_WIDTH = 80
local DEFAULT_DECORATION_CHAR = '#'

local function centerText(text, width)
    local padding = width - #text
    if padding <= 0 then return text end
    local left_pad = math.floor(padding / 2)
    return string.format(
        "%s%s%s",
        string.rep(" ", left_pad),
        text,
        string.rep(" ", padding - left_pad)
    )
end

local function InsertHeader(text, options)
    options = options or {}
    local width = options.width or DEFAULT_WIDTH
    local decorator = options.decorationChar or DEFAULT_DECORATION_CHAR

    -- Ensure minimal readable width
    local min_header_width = #text + 4  -- Accounts for ' # ' spacing and 2 decorations
    width = math.max(width, min_header_width)

    -- Build header elements
    local full_line = string.rep(decorator, width)
    local centered = centerText(string.format(" %s ", text), width - 2)
    local middle_line = string.format("%s%s%s", decorator, centered, decorator)

    -- Combine header lines
    local header_lines = {
        full_line,
        middle_line,
        full_line
    }

    -- Insert header into the buffer at the current cursor position
    local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- Get current cursor position (1-indexed)
    row = row - 1 -- Convert to 0-indexed for API compatibility

    vim.api.nvim_buf_set_text(0, row, col, row, col, header_lines) -- Insert lines at the cursor position
end

vim.api.nvim_create_user_command(
  'InsertHeader',
  function(opts)
      InsertHeader(opts.args)
  end,
  { nargs = 1 }
)

vim.keymap.set('n', '<leader>ih', function()
    InsertHeader("{{title}}")
end, { noremap = true })
