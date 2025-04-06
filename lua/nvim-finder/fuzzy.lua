---@class Finder.FuzzyInput
---@field [1] table<Finder.Entry>
---@field [2] fun(selected: string)
---@field prompt string
---@function new_fuzzy_finder
---@param input Finder.FuzzyInput
return function(input)
    assert(input, "input is required")
    assert(input[1], "opts[1] source is required, should be a table")
    assert(type(input[1]) == "table")
    assert(input[2], "opts.[2] on_accept is required")

    local opts = {
        [1] = input[1],
        [2] = input[2],
        user_input = "",
        prompt = input.prompt or '> '
    }

    opts.source = opts[1]

    opts.on_accept = opts[2]

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
    vim.fn.prompt_setprompt(buf, opts.prompt)

    local width = math.floor(vim.o.columns * 0.7)
    local height = math.floor(vim.o.lines * 0.8)
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

    vim.cmd [[ startinsert ]]

    opts.hl_ns = vim.api.nvim_create_namespace("nvim-fuzzy")

    function opts.update(opts)
        local prev = opts.user_input
        local prompt_line = vim.api.nvim_get_current_line()

        opts.user_input = prompt_line:sub(#opts.prompt + 1)
        opts.scores = {}
        opts.buf_lines = {}

        --TODO(amirreza): there should be a better way than 3 loops ...
        local start = vim.uv.hrtime()
        if prev ~= opts.user_input then
            opts.source = require("nvim-finder.alg.fzy")(opts.user_input, opts.source)
            table.sort(opts.source, function(a, b)
                return (a.score) < (b.score)
            end)
        end

        local sort_elapsed = (vim.uv.hrtime() - start) / 1e6

        for _, v in ipairs(opts.source) do
            table.insert(opts.buf_lines, string.format("%f %s", v.score, v.display))
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
        vim.cmd([[ quit! ]])
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

    vim.schedule(function()
        opts:update()
    end)
end
