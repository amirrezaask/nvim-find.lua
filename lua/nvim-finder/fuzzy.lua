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
    -- local sorting_function = opts.sorting_function or require('nvim-finder.alg.fzy')
    -- local sorting_function = opts.sorting_function or require('nvim-finder.alg.fzf')
    local buf_lines = {}
    local selected_item = nil
    local include_scores = opts.include_scores or true
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
        -- border = "rounded",
    })
    vim.api.nvim_set_option_value('bufhidden', 'delete', { buf = buf })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('ul', -1, { buf = buf })
    vim.api.nvim_set_option_value('concealcursor', 'nc', { win = win })

    local visible_start = 0
    local view_height = (height - 1)

    if opts.set_winbar then vim.api.nvim_set_option_value('winbar', title, { win = win }) end

    vim.cmd [[ startinsert ]]

    local hl_ns = vim.api.nvim_create_namespace("nvim-finder.fuzzy")

    local function update()
        if not should_update then return end
        if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end

        local prev = user_input
        local prompt_line = vim.api.nvim_get_current_line()

        user_input = prompt_line:sub(#prompt + 1)
        buf_lines = {}

        local t0 = vim.uv.hrtime()
        if prev ~= user_input then
            sorting_function(user_input, source)
            table.sort(source, function(a, b)
                return (a.score) < (b.score)
            end)
        end
        local t1 = vim.uv.hrtime() -- after sorting



        frame_source = {}
        for _, v in ipairs(
            table.sub(
                source,
                visible_start,
                visible_start + view_height
            )) do
            if v.matched ~= false then
                table.insert(frame_source, v)
            end
        end



        local added_lines = 0
        if #frame_source < (view_height) then
            for i = 1, (view_height) - #frame_source do
                added_lines = added_lines + 1
                table.insert(buf_lines, i, "")
            end
        end

        if selected_item == nil then
            selected_item = view_height - 1
        end


        if selected_item < 0 then
            selected_item = 1
        end


        for _, v in ipairs(frame_source) do
            local score_prefix = string.format("%X ", v.score)
            if not include_scores then score_prefix = "" end
            local line = padding .. score_prefix .. v.display
            if #line < width then
                line = line .. string.rep(" ", width - #line)
            end

            table.insert(buf_lines, line)
        end


        vim.api.nvim_buf_set_lines(buf, 0, -2, false, buf_lines)

        _ = FINDER_FUZZY_DEBUG and print(
            "Entries", #source,
            "Cost", (t1 - t0) / 10e6
        )

        vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)

        vim.hl.range(buf, hl_ns, "Question", { selected_item, 0 }, { selected_item, -1 })
        vim.hl.range(buf, hl_ns, "Visual", { selected_item, 0 }, { selected_item, -1 })

        should_update = false
    end

    local function shift_cursor(delta)
        local old = selected_item
        selected_item = selected_item + delta

        local added_lines = (view_height) - #frame_source

        if selected_item >= view_height then
            selected_item = added_lines
        elseif selected_item <= view_height - added_lines then
            selected_item = view_height - 1
        end

        -- if selected_item < visible_start then
        --     visible_start = selected_item - 1
        -- elseif selected_item > visible_start + view_height then
        --     visible_start = visible_start + 1
        -- end

        print(("#source=%d #frame=%d view_height=%d old=%d sel=%d"):format(#source, #frame_source, view_height, old,
            selected_item))
    end

    local function down()
        shift_cursor(1)
        should_update = true
        update()
    end

    local function up()
        shift_cursor(-1)
        should_update = true
        update()
    end

    local function quit()
        vim.api.nvim_win_close(win, true)
        vim.api.nvim_buf_delete(buf, { force = true })
    end

    local function accept()
        local idx = selected_item + 1
        if height < #frame_source then
            local view_offset = #frame_source - height - 2
            idx = selected_item + view_offset + 1
        elseif #frame_source < view_height then
            local added_lines = (view_height) - #frame_source
            idx = (selected_item + 1) - added_lines
        end
        local item = frame_source[idx].entry
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        quit()
        on_accept(item)
    end

    vim.keymap.set({ "n", "i" }, "<C-p>", function()
        up()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<C-n>", function()
        down()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<CR>", function()
        accept()
    end, { buffer = buf })

    vim.keymap.set({ "n", "i" }, "<C-c>", function()
        quit()
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
    timer:start(10, REFRESH_MS, vim.schedule_wrap(function()
        update()
    end))

    if type(opts[1]) == 'function' then
        opts[1](function(e)
            for _, v in ipairs(e) do
                table.insert(source, v)
            end
            should_update = true
        end)
    else
        source = {}
        should_update = true
        source = opts[1]
    end


    update()
end

-- require("nvim-finder").__reload()
-- F = require("nvim-finder")


return floating_fuzzy
