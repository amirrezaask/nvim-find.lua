local REFRESH_MS = 15 -- every 15 milliseconds we refresh fuzzy window if there is a need for updating.

function table.sub(t, i, j)
    local result = {}
    for k = i or 1, j or #t do
        result[#result + 1] = t[k]
    end
    return result
end

---@class Finder.FuzzyOpts
---@field [1] table<Finder.Entry> | fun(cb: fun(new_entry))
---@field [2] fun(selected_entry: string)
---@field prompt? string
---@field title?  string
---@field padding? string
---@field sorting_function fun(query: string, collection: table<Finder.Entry>)
---@field width_ratio number
---@field height_ratio number
local function floating_fuzzy(opts)
    assert(opts, "opts is required")
    assert(opts[1], "opts[1] source is required")
    assert(opts[2], "opts[2] on_accept is required")

    local should_update = false

    local user_input = ""
    local prompt = opts.prompt or '> '
    local title = opts.title or 'Fuzzy Finder'
    local source = {}
    local padding = opts.padding or '  '
    local sorting_function = opts.sorting_function or require('nvim-finder.alg.ngram-indexing')
    local buf_lines = {}
    local selected_item = 0
    local include_scores = opts.include_scores ~= false
    local frame_source = {}

    local on_accept = opts[2]

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
    vim.fn.prompt_setprompt(buf, prompt)

    local width = math.floor(vim.o.columns * (opts.width_ratio or 0.5))
    local height = math.floor(vim.o.lines * (opts.height_ratio or 0.65))
    local row = math.floor(vim.o.lines - height)
    local col = math.floor((vim.o.columns - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
    })
    vim.api.nvim_set_option_value('bufhidden', 'delete', { buf = buf })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('ul', -1, { buf = buf })
    vim.api.nvim_set_option_value('concealcursor', 'nc', { win = win })

    local view_height = height - 1
    local visible_start = 0

    if opts.set_winbar then
        vim.api.nvim_set_option_value('winbar', title, { win = win })
    end

    vim.cmd [[ startinsert ]]

    local hl_ns = vim.api.nvim_create_namespace("nvim-finder.fuzzy")

    local function update()
        if not should_update then return end
        if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end

        local prev = user_input
        local prompt_line = vim.api.nvim_get_current_line()
        user_input = prompt_line:sub(#prompt + 1)
        buf_lines = {}

        if prev ~= user_input then
            sorting_function(user_input, source)
            table.sort(source, function(a, b)
                return a.score < b.score
            end)

            selected_item = math.max(0, #source - 1)
            visible_start = math.max(0, #source - view_height)
        end

        frame_source = {}
        for _, v in ipairs(table.sub(source, visible_start + 1, visible_start + view_height)) do
            if v.matched ~= false then
                table.insert(frame_source, v)
            end
        end

        local pad_lines = view_height - #frame_source
        for _ = 1, pad_lines do
            table.insert(buf_lines, "")
        end

        for _, v in ipairs(frame_source) do
            local score_prefix = include_scores and string.format("%X ", v.score) or ""
            local line = padding .. score_prefix .. v.display
            if #line < width then
                line = line .. string.rep(" ", width - #line)
            end
            table.insert(buf_lines, line)
        end

        vim.api.nvim_buf_set_lines(buf, 0, height - 1, false, buf_lines)

        vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)

        local highlight_line = pad_lines + (selected_item - visible_start)
        if highlight_line >= 0 and highlight_line < view_height then
            vim.hl.range(buf, hl_ns, "Question", { highlight_line, 0 }, { highlight_line, -1 })
            vim.hl.range(buf, hl_ns, "Visual", { highlight_line, 0 }, { highlight_line, -1 })
        end

        should_update = false
    end

    local function shift_cursor(delta)
        if #source == 0 then return end
        selected_item = (selected_item + delta + #source) % #source

        if selected_item < visible_start then
            visible_start = selected_item
        elseif selected_item >= visible_start + view_height then
            visible_start = selected_item - view_height + 1
        end

        visible_start = math.max(0, visible_start)

        should_update = true
        update()
    end

    local function down() shift_cursor(1) end
    local function up() shift_cursor(-1) end
    local function page_down() shift_cursor(view_height) end
    local function page_up() shift_cursor(-view_height) end

    local function quit()
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end

    local function accept()
        if not source[selected_item + 1] then return end
        local item = source[selected_item + 1].entry
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        quit()
        on_accept(item)
    end

    vim.keymap.set({ "n", "i" }, "<C-p>", up, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-n>", down, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<up>", up, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<down>", down, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-u>", page_up, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-d>", page_down, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<CR>", accept, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-c>", quit, { buffer = buf })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end
            should_update = true
            update()
        end,
    })

    local timer = vim.uv.new_timer()
    timer:start(10, REFRESH_MS, vim.schedule_wrap(function()
        update()
    end))

    local function initialize_source(entries)
        source = entries
        selected_item = math.max(0, math.min(#source - 1, #source - 1))
        visible_start = math.max(0, #source - view_height)
        should_update = true
    end

    if type(opts[1]) == 'function' then
        opts[1](function(e)
            initialize_source(e)
        end)
    else
        initialize_source(opts[1])
    end

    update()
end

return floating_fuzzy
