function table.sub(t, i, j)
    local result = {}
    for k = i or 1, j or #t do
        result[#result + 1] = t[k]
    end
    return result
end

---@class Finder.FuzzyOpts
---@field [1] table<Finder.Entry> | fun(update_notifier: fun(new_entry))
---@field [2] fun(selected_entry: string)
---@field prompt string
local function floating_fuzzy(opts)
    assert(opts, "input is required")
    assert(opts[1], "opts[1] source is required")
    assert(opts[2], "opts[2] on_accept is required")

    local should_update = false

    local user_input = ""
    local prompt = opts.prompt or '> '
    local title = opts.title or 'Fuzzy Finder'
    local source = {}
    local padding = opts.padding or '  '
    local sorting_function = opts.sorting_function or require('nvim-finder.alg.fzf')
    local buf_lines = {}
    local selected_item = 0


    local on_accept = opts[2]

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
    vim.fn.prompt_setprompt(buf, prompt)

    local width = math.floor(vim.o.columns * (opts.width_ratio or 0.7))
    local height = math.floor(vim.o.lines * (opts.height_ratio or 0.9))
    local row = math.floor(vim.o.lines - height)
    local col = math.floor((vim.o.columns - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        -- border = "rounded",
    })
    vim.api.nvim_set_option_value('bufhidden', 'delete', { buf = buf })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('ul', -1, { buf = buf })
    vim.api.nvim_set_option_value('concealcursor', 'nc', { win = win })

    local view_height = (height - 1)

    if opts.set_winbar then vim.api.nvim_set_option_value('winbar', opts.title, { win = win }) end

    vim.cmd [[ startinsert ]]

    local hl_ns = vim.api.nvim_create_namespace("nvim-finder.fuzzy")

    local function update()
        if not should_update then return end
        if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
            return
        end
        local prev = user_input
        local prompt_line = vim.api.nvim_get_current_line()

        user_input = prompt_line:sub(#prompt + 1)
        buf_lines = {}

        local start = vim.uv.hrtime()
        if prev ~= user_input then
            source = sorting_function(user_input, source)
            table.sort(source, function(a, b)
                return (a.score) < (b.score)
            end)
        end
        local result_count = 0
        opts.view_height = (height - 1)

        local sort_elapsed = (vim.uv.hrtime() - start) / 1e6
        opts.this_frame_source = {}
        for _, v in ipairs(table.sub(source, #source - view_height, #source)) do
            if v.matched ~= false then
                result_count = result_count + 1
                table.insert(opts.this_frame_source, v)
            end
        end


        local added_lines = 0
        if #opts.this_frame_source < (view_height) then
            for i = 1, (view_height) - #opts.this_frame_source do
                added_lines = added_lines + 1
                table.insert(buf_lines, i, "")
            end
        end

        for _, v in ipairs(opts.this_frame_source) do
            table.insert(buf_lines, string.format(padding .. "%X %s", v.score, v.display))
        end


        vim.api.nvim_buf_set_lines(buf, 0, -2, false, buf_lines)

        -- vim.api.nvim_win_set_cursor(win, { #opts.buf_lines + 1, #opts.user_input + #opts.prompt })

        local actual_lines = #opts.this_frame_source + added_lines

        print(
            "Entries", #source,
            "Cost", sort_elapsed
        )

        if selected_item == nil then selected_item = actual_lines - 1 end
        if selected_item < actual_lines - result_count then
            selected_item = actual_lines - 1
        end

        if selected_item >= actual_lines then
            selected_item = added_lines
        end

        vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)

        vim.hl.range(buf, hl_ns, "Question", { selected_item, 0 }, { selected_item, width })
        vim.hl.range(buf, hl_ns, "Visual", { selected_item, 0 }, { selected_item, width })

        should_update = false
    end

    vim.keymap.set({ "n", "i" }, "<C-n>", function()
        selected_item = selected_item + 1
        should_update = true
        update()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<C-p>", function()
        selected_item = selected_item - 1
        should_update = true
        update()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<CR>", function()
        local idx = selected_item + 1
        if height < #opts.this_frame_source then
            local view_offset = #opts.this_frame_source - height - 2
            idx = selected_item + view_offset + 1
        elseif #opts.this_frame_source < opts.view_height then
            local added_lines = (opts.view_height) - #opts.this_frame_source
            idx = (selected_item + 1) - added_lines
        end
        local item = opts.this_frame_source[idx].entry
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
        on_accept(item)
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<C-c>", function()
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
                return
            end
            should_update = true
            update()
        end,
    })


    local timer = vim.uv.new_timer()
    timer:start(10, 100, vim.schedule_wrap(function()
        update()
    end))

    if type(opts[1]) == 'function' then
        opts[1](function(e)
            for _, v in ipairs(e) do
                table.insert(source, v)
            end
            selected_item = -1
            should_update = true
        end)
    else
        source = {}
        should_update = true
        source = opts[1]
    end

    update()
end

require("nvim-finder").__reload()
F = require("nvim-finder")


return floating_fuzzy
