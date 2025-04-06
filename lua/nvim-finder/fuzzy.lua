---@class Finder.FuzzyOpts
---@field [1] table<Finder.Entry> | fun(update_notifier: fun(new_entry))
---@field [2] fun(selected_entry: string)
---@field prompt string
local function fuzzy(opts)
    assert(opts, "input is required")
    assert(opts[1], "opts[1] source is required, should be a table")
    assert(opts[2], "opts[2] on_accept is required")

    opts.user_input = ""
    opts.prompt = opts.prompt or '> '
    opts.title = opts.title or 'Fuzzy Finder'
    opts.source = {}
    opts.source_function_calling_convention = opts.source_function_calling_convention or 'once'

    opts.on_accept = opts[2]

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
    vim.fn.prompt_setprompt(buf, opts.prompt)

    vim.print(opts.height_ratio)
    local width = math.floor(vim.o.columns * (opts.width_ratio or 0.7))
    local height = math.floor(vim.o.lines * (opts.height_ratio or 0.8))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })


    vim.api.nvim_set_option_value('winbar', opts.title, { win = win })

    vim.cmd [[ startinsert ]]

    opts.hl_ns = vim.api.nvim_create_namespace("nvim-fuzzy")

    function opts.update(opts)
        local prev = opts.user_input
        local prompt_line = vim.api.nvim_get_current_line()

        opts.user_input = prompt_line:sub(#opts.prompt + 1)
        opts.scores = {}
        opts.buf_lines = {}

        local start = vim.uv.hrtime()
        if prev ~= opts.user_input then
            opts.source = require("nvim-finder.alg.fzy")(opts.user_input, opts.source)
            table.sort(opts.source, function(a, b)
                return (a.score) < (b.score)
            end)
        end

        local sort_elapsed = (vim.uv.hrtime() - start) / 1e6

        for _, v in ipairs(opts.source) do
            table.insert(opts.buf_lines, string.format("%s", v.display))
        end

        vim.api.nvim_buf_set_lines(buf, 0, -2, false, opts.buf_lines)
        vim.api.nvim_win_set_cursor(win, { #opts.buf_lines + 1, #opts.user_input + #opts.prompt })

        local actual_lines = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)

        print(
            "Entries", #opts.source,
            "Cost", sort_elapsed, "ms"
        )
        if opts.selected_item == nil then opts.selected_item = actual_lines - 1 end
        if opts.selected_item < 0 then
            opts.selected_item = actual_lines - 1
        end

        if opts.selected_item >= actual_lines then
            opts.selected_item = 0
        end

        vim.api.nvim_buf_clear_namespace(buf, opts.hl_ns, 0, -1)

        vim.hl.range(buf, opts.hl_ns, "Question", { opts.selected_item, 0 }, { opts.selected_item, width })
    end

    vim.keymap.set({ "n", "i" }, "<C-n>", function()
        opts.selected_item = opts.selected_item + 1
        opts:update()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<C-p>", function()
        opts.selected_item = opts.selected_item - 1
        opts:update()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<CR>", function()
        local item = opts.source[opts.selected_item + 1].entry
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
        vim.print(item)
        opts.on_accept(item)
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<C-c>", function()
        vim.cmd([[ quit! ]])
    end, { buffer = buf })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            opts:update()
        end,
    })

    if type(opts[1]) == 'function' then
        opts[1](function(e)
            table.insert(opts.source, e)
            opts.selected_item = -1
            vim.schedule(function() opts:update() end)
        end)
    else
        opts.source = opts[1]
    end

    vim.schedule(function()
        opts:update()
    end)
end



return fuzzy
