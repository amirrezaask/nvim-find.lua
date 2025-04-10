---@class Finder.Entry
---@field data any
---@field score number
---@field display string

---@class Finder.FuzzyOpts
---@field [1] table<Finder.Entry> | fun(cb: fun(new_entry))
---@field [2] fun(selected_entry: any)
---@field prompt? string
---@field title?  string
---@field padding? string
---@field sorting_function fun(query: string, collection: table<Finder.Entry>)
---@field width_ratio number
---@field height_ratio number
---@field live? boolean

local M = {}
local sorting = require("nvim-finder.sorting")

function M.floating_fuzzy(opts)
    assert(opts, "opts is required")
    assert(opts[1], "opts[1] source is required")
    assert(opts[2], "opts[2] on_accept is required")

    function table.sub(t, i, j)
        local result = {}
        for k = i or 1, j or #t do
            result[#result + 1] = t[k]
        end
        return result
    end

    local REFRESH_MS = 15 -- every 15 milliseconds we refresh fuzzy window if there is a need for updating.
    local should_update = false

    local user_input = ""
    local prompt_char = opts.prompt_char or '❯ '
    local prompt = (opts.prompt or " ") .. prompt_char
    local source = {}
    local padding = opts.padding or '  '
    local sorting_function = opts.sorting_function or sorting.ngram_indexing
    local buf_lines = {}
    local selected_item = 0
    local get_qf_entry = opts.get_qf_entry or function(e)
        return {
            {
                filename = e.data.filename,
                lnum = e.data.line,
                col = e.data.column,
                text = e.display
            }
        }
    end
    local include_scores = opts.include_scores ~= false
    local frame_source = {}
    local get_window_config = opts.get_window_config or function()
        local width = math.floor(vim.o.columns * (opts.width_ratio or 0.9))
        local height = math.floor(vim.o.lines * (opts.height_ratio or 0.65))
        local row = math.floor(vim.o.lines - height)
        local col = math.floor((vim.o.columns - width) / 2)
        return {
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            style = "minimal",
            zindex = 100, -- Ensure it’s above other windows
            border = 'rounded'
        }
    end


    local on_accept = opts[2]

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
    vim.fn.prompt_setprompt(buf, prompt)

    local window_config = get_window_config()
    local win = vim.api.nvim_open_win(buf, true, window_config)
    vim.api.nvim_set_option_value('bufhidden', 'delete', { buf = buf })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('ul', -1, { buf = buf })
    vim.api.nvim_set_option_value('concealcursor', 'nc', { win = win })

    local view_height = window_config.height - 1
    local visible_start = 0


    vim.api.nvim_create_autocmd("VimResized", {
        buffer = buf,
        callback = function()
            window_config = get_window_config()
            vim.api.nvim_win_set_config(win, window_config)
            view_height = window_config.height - 1
            should_update = true
        end
    })


    local function update_source(entries)
        if opts.live then
            source = entries
        else
            for _, entry in ipairs(entries) do
                table.insert(source, entry)
            end
        end
        -- Always start with selection at the bottom
        selected_item = math.max(0, #source - 1)
        visible_start = math.max(0, #source - view_height)
        should_update = true
    end

    local hl_ns = vim.api.nvim_create_namespace("nvim-finder.fuzzy")

    local function update()
        if not should_update then return end
        if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end

        local prev = user_input
        local prompt_line = vim.api.nvim_get_current_line()
        user_input = prompt_line:sub(#prompt + 1)
        buf_lines = {}

        if prev ~= user_input then
            if opts.live then
                opts[1](function(e)
                    update_source(e)
                end, user_input)
            else
                sorting_function(user_input, source)
                table.sort(source, function(a, b)
                    return a.score < b.score
                end)
            end
            -- Always select the last item when input changes
            selected_item = math.max(0, #source - 1)
            -- Adjust visible_start to show the bottom
            visible_start = math.max(0, #source - view_height)
        end

        frame_source = {}
        local visible_end = math.min(visible_start + view_height, #source)
        for i = visible_start + 1, visible_end do
            table.insert(frame_source, source[i])
        end

        local pad_lines = view_height - #frame_source
        for _ = 1, pad_lines do
            table.insert(buf_lines, "")
        end

        for _, v in ipairs(frame_source) do
            local score_prefix = include_scores and string.format("%X ", v.score) or ""
            local line = padding .. score_prefix .. v.display
            if #line < window_config.width then
                line = line .. string.rep(" ", window_config.width - #line)
            end
            table.insert(buf_lines, line)
        end

        vim.api.nvim_buf_set_lines(buf, 0, window_config.height - 1, false, buf_lines)

        vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)

        local highlight_line = pad_lines + (selected_item - visible_start)
        if highlight_line >= 0 and highlight_line < view_height then
            vim.hl.range(buf, hl_ns, "Question", { highlight_line, 0 }, { highlight_line, -1 })
            vim.hl.range(buf, hl_ns, "Visual", { highlight_line, 0 }, { highlight_line, -1 })
        end

        vim.schedule(function()
            vim.cmd [[ startinsert ]]
        end)
        should_update = false
    end

    local function shift_cursor(delta)
        if #source == 0 then return end
        local new_selected = (selected_item + delta + #source) % #source

        selected_item = new_selected
        if selected_item < visible_start then
            visible_start = selected_item
        elseif selected_item >= visible_start + view_height then
            visible_start = selected_item - view_height + 1
        end
        visible_start = math.max(0, math.min(visible_start, #source - view_height))

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
        local item = source[selected_item + 1].data
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
        quit()
        on_accept(item)
    end

    local function export_to_qf()
        for _, e in ipairs(source) do
            vim.fn.setqflist(get_qf_entry(e), 'a')
        end
        quit()
    end

    vim.keymap.set({ "n", "i" }, "<C-p>", up, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-n>", down, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<up>", up, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<down>", down, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-u>", page_up, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-d>", page_down, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<CR>", accept, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-c>", quit, { buffer = buf })
    vim.keymap.set({ "n", "i" }, "<C-q>", export_to_qf, { buffer = buf })

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

    if type(opts[1]) == 'function' then
        opts[1](function(e)
            update_source(e)
        end)
    else
        update_source(opts[1])
    end

    update()
end

function M.__reload()
    package.loaded["nvim-finder"] = nil
    package.loaded["nvim-finder.sorting"] = nil
end

local function read_output_by_line(program, args, cwd, line_to_entry)
    return function(cb)
        local uv = vim.uv
        local handle
        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)

        handle = uv.spawn(program, {
            args = args,
            cwd = cwd,
            stdio = { nil, stdout, stderr },
        }, function(code, signal)
            stdout:read_stop()
            stdout:close()
            handle:close()
        end)

        uv.read_start(stderr, function(err, data)
            if err then
                print("stderr " .. program, err)
                return
            end
            if data then
                print("stderr " .. program, data)
            end
        end)

        uv.read_start(stdout, function(err, data)
            if err then
                print(program, err)
                return
            end
            local results = {}
            if data then
                local lines = vim.split(data, "\n")
                for _, line in ipairs(lines) do
                    if line ~= "" then
                        local entry = line_to_entry(line)
                        if entry ~= nil then
                            table.insert(results, entry)
                        end
                    end
                end
                cb(results)
            end
        end)
    end
end
local function shorten_path(path)
    local THRESHOLD = 80
    if not path or path == "" then
        return ""
    end

    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    local is_absolute = path:sub(1, 1) == "/"

    if #parts <= 1 then
        return path
    end

    -- Build the shortened path
    local result = {}
    for i, part in ipairs(parts) do
        if i >= #parts - 1 then
            table.insert(result, part)
        else
            table.insert(result, part:sub(1, 1))
        end
    end

    -- Join components and add leading slash if original was absolute
    local shortened = table.concat(result, "/")
    if is_absolute then
        shortened = "/" .. shortened
    end

    if #path < THRESHOLD then return path end

    return shortened
end

---@class Finder.FilesOpts: Finder.FuzzyOpts
---@field path string path to set as CWD, if not set it will be root of git repository.
---@param opts Finder.FilesOpts
function M.files(opts)
    ---@type Finder.FilesOpts
    opts = opts or {}
    opts.path = opts.path or vim.fs.root(vim.fn.getcwd(), ".git") or vim.fn.getcwd()
    opts.title = opts.title or ('Files ' .. opts.path)
    opts.prompt = ''
    opts.width_ratio = 0.55
    opts.height_ratio = 0.85

    local function luv_find(opts)
        opts = opts or {}

        local expand = require("nvim-finder.path").expand
        local uv = vim.loop
        opts.path = expand(opts.path) -- nil check
        if opts.path == nil then return end
        if opts.starting_directory == nil then opts.starting_directory = opts.path end
        opts.hidden = opts.hidden or false
        opts.exclude = opts.exclude or {}
        opts.shorten_paths = opts.shorten_paths or true

        -- Normalize exclude to a list of glob patterns
        local exclude_patterns = {}
        if type(opts.exclude) == "string" then
            exclude_patterns = { opts.exclude }
        elseif vim.islist(opts.exclude) then
            exclude_patterns = opts.exclude
        end

        -- Checks if a path matches any exclude glob
        local function is_excluded(entry_path)
            for _, pattern in ipairs(exclude_patterns) do
                if entry_path:match(pattern) then
                    return true
                end
            end
            return false
        end

        return function(cb)
            uv.fs_opendir(opts.path, function(err, dir)
                if err then
                    -- log("error reading directory", err)
                    return
                end

                local function continue_reading_fs_entries()
                    uv.fs_readdir(dir, function(err, entries)
                        if err then
                            uv.fs_closedir(dir)
                            -- log("error in reading directory", err)
                            return
                        end


                        local files = {}

                        if not entries then
                            uv.fs_closedir(dir)
                            return
                        end

                        for _, entry in ipairs(entries) do
                            local entry_path = opts.path .. "/" .. entry.name

                            -- Skip excluded entries based on glob
                            if is_excluded(entry_path) then
                                goto continue
                            end

                            -- Skip hidden files unless opts.hidden is true
                            if not opts.hidden and entry.name:sub(1, 1) == "." then
                                goto continue
                            end

                            if entry.type == 'file' then
                                local display_path = entry_path
                                if opts.shorten_paths then
                                    display_path = shorten_path(display_path)
                                end
                                table.insert(files, {
                                    data = {
                                        filename = entry_path,
                                    },
                                    display = display_path,
                                    score = 0
                                })
                            elseif entry.type == "directory" then
                                local new_opts = {}
                                for k, v in pairs(opts) do
                                    new_opts[k] = v
                                end
                                new_opts.path = entry_path
                                vim.schedule(function()
                                    local f = luv_find(new_opts)
                                    if f == nil then return end
                                    f(cb)
                                end)
                            end

                            cb(files)

                            ::continue::
                        end

                        continue_reading_fs_entries()
                    end)
                end

                continue_reading_fs_entries()
            end)
        end
    end

    local function find(opts)
        opts.cwd = vim.fn.expand(opts.cwd or vim.fs.root(vim.fn.getcwd(), '.git'))
        --TODO(amirrez): support excludes
        return read_output_by_line("find",
            opts.args or { opts.cwd, "-type", "f", "-not", "-path", "**/.git/*", "-not", "-path", "**/vendor/*" },
            opts.cwd,
            function(line)
                return {
                    data = { filename = line },
                    score = 0,
                    display = line:sub(#opts.path + 1)
                }
            end
        )
    end

    if vim.fn.executable("find") == 1 then
        opts[1] = find(opts)
    else
        opts[1] = luv_find(opts)
    end

    opts[2] = function(e)
        vim.cmd.edit(e.filename)
    end

    M.floating_fuzzy(opts)
end

local function parse_ripgrep_line(line)
    local filepath, lineno, col, match = line:match("^.-%s+(.-):(%d+):(%d+):(.*)")
    if not filepath then
        filepath, lineno, col, match = line:match("^(.-):(%d+):(%d+):(.*)")
    end

    if filepath and lineno and col and match then
        return {
            filename = filepath,
            line = tonumber(lineno),
            col = tonumber(col),
            match = match,
        }
    end

    -- log("Could not parse line ", line)
    return nil
end


function M.ripgrep_qf(opts)
    opts = opts or {}
    vim.ui.input({ prompt = "Ripgrep> " }, function(s)
        if s == nil then return end
        opts.cwd = opts.cwd or vim.fs.root(0, '.git') or vim.fn.expand("%:p:h")
        local uv = vim.uv
        local handle
        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)
        local path = vim.fn.expand(opts.cwd)

        handle = uv.spawn("rg", {
            args = { "--color", "never", "--column", "-n", "--no-heading", s },
            cwd = path,
            stdio = { nil, stdout, stderr },
        }, function(code, signal)
            stdout:read_stop()
            stdout:close()
            handle:close()
            vim.schedule(function()
                vim.cmd.copen()
            end)
        end)

        uv.read_start(stderr, function(err, data)
            if err then
                -- log("stderr ", err)
                return
            end
            if data then
                -- log("stderr ", data)
            end
        end)

        uv.read_start(stdout, function(err, data)
            if err then
                vim.schedule(function()
                    -- log(err)
                end)
                return
            end
            if data then
                local lines = vim.split(data, "\n")
                for _, line in ipairs(lines) do
                    if line ~= "" then
                        local e = parse_ripgrep_line(line)
                        if e ~= nil then
                            vim.schedule(function()
                                local filename = vim.fs.joinpath(path, e.file)
                                vim.fn.setqflist(
                                    { { filename = filename, lnum = e.line, col = e.column, text = e.match } },
                                    'a')
                            end)
                        end
                    end
                end
            end
        end)
    end)
end

---@class Finder.RipgrepFuzzy: Finder.FuzzyOpts
function M.ripgrep_fuzzy(opts)
    opts = opts or {}
    opts.cwd = opts.cwd or vim.fs.root(vim.fn.getcwd(), '.git')

    vim.ui.input({ prompt = opts.prompt or "Fuzzy Ripgrep> " }, function(s)
        if s == nil then return end
        opts[1] = read_output_by_line("rg", { "--color", "never", "--column", "-n", "--no-heading", s },
            opts.cwd, function(line)
                if line == "" then return {} end
                local e = parse_ripgrep_line(line)
                if e == nil then return nil end

                return { data = e, score = 0, display = e.filename .. ": " .. vim.trim(e.match) }
            end)
        opts[2] = function(e)
            vim.cmd.edit(e.file)
            vim.api.nvim_win_set_cursor(0, { e.line, e.col })
        end
        opts.title = opts.title or ('Rg ' .. opts.cwd)

        M.floating_fuzzy(opts)
    end)
end

function M.live_ripgrep(opts)
end

function M.diagnostics(opts)
    opts = opts or {}
    local diags = vim.diagnostic.get(opts.buf, {})
    local entries = {}
    for _, diag in ipairs(diags) do
        local filename = vim.api.nvim_buf_get_name(diag.bufnr)
        local severity = diag.severity
        severity = type(severity) == "number" and vim.diagnostic.severity[severity] or severity
        table.insert(entries, {
            display = string.format("[%s] %s %s", severity, require("nvim-finder.path").shorten(filename), diag.message),
            score = 0,
            data = {
                filename = filename,
                line = diag.lnum,
            }
        })
    end
    opts[1] = entries
    opts[2] = function(e)
        vim.cmd.edit(e.filename)
        vim.api.nvim_win_set_cursor(0, { e.line, 0 })
    end

    M.floating_fuzzy(opts)
end

---@class Finder.BuffersOpts: Finder.FuzzyOpts
---@param opts Finder.BuffersOpts
function M.buffers(opts)
    opts = opts or {}
    local buffers = {}
    local current_buf = vim.api.nvim_get_current_buf()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local keep = (opts.hidden or vim.bo[buf].buflisted)
            and (opts.unloaded or vim.api.nvim_buf_is_loaded(buf))
            and (opts.current or buf ~= current_buf)
            and (opts.nofile or vim.bo[buf].buftype ~= "nofile")
            and (not opts.modified or vim.bo[buf].modified)
        if keep then
            local name = vim.api.nvim_buf_get_name(buf)
            if name == "" then
                name = "[No Name]" .. (vim.bo[buf].filetype ~= "" and " " .. vim.bo[buf].filetype or "")
            end
            table.insert(buffers, { display = name, data = buf, score = 0 })
        end
    end
    opts[1] = buffers
    opts[2] = function(e)
        vim.api.nvim_set_current_buf(e)
    end


    M.floating_fuzzy(opts)
end

---@class Finder.HelpTagsOpts: Finder.FuzzyOpts
function M.helptags(opts)
    opts = opts or {}
    local help_tags = {}
    -- Get all runtime paths
    local rtp = vim.api.nvim_list_runtime_paths()
    for _, path in ipairs(rtp) do
        local tagfile = path .. "/doc/tags"
        local f = io.open(tagfile, "r")
        if f then
            for line in f:lines() do
                local tag = line:match("^([^\t]+)")
                if tag then
                    table.insert(help_tags, { data = tag, display = tag, score = 0 })
                end
            end
            f:close()
        end
    end
    opts[1] = help_tags

    opts[2] = function(e)
        vim.cmd.help(e)
    end

    M.floating_fuzzy(opts)
end

---@class Finder.GitFilesOpts: Finder.FuzzyOpts
function M.git_files(opts)
    opts = opts or {}
    opts.path = opts.path or vim.fs.root(vim.fn.getcwd(), '.git')
    opts[1] = read_output_by_line("git",
        { "ls-files" },
        opts.cwd,
        function(line)
            local path = line
            -- if opts.shorten_paths then
            --     path = require("nvim-finder.path").shorten(path)
            -- end
            return { data = line, score = 0, display = path }
        end)

    opts[2] = function(e)
        vim.cmd.edit(e)
    end

    M.floating_fuzzy(opts)
end

---@class Finder.OldFilesOpts: Finder.FuzzyOpts
function M.oldfiles(opts)
    opts = opts or {}
    opts[1] = {}

    for _, v in ipairs(vim.v.oldfiles) do
        table.insert(opts[1], { data = v, display = v, score = 0 })
    end

    opts[2] = function(e)
        vim.cmd.edit(e)
    end

    M.floating_fuzzy(opts)
end

local function make_display_from_lsp_result(filename, sym, line)
    return string.format(
        "[%s] %s",
        sym.kind,
        sym.name
    )
end


---@class Finder.LspDocumentSymbolsOpts: Finder.FuzzyOpts
function M.lsp_document_symbols(opts)
    opts = opts or {}
    opts.buf = opts.buf or vim.api.nvim_get_current_buf()

    opts[1] = function(callback)
        local params = { textDocument = vim.lsp.util.make_text_document_params(opts.buf) }

        vim.lsp.buf_request_all(opts.buf, 'textDocument/documentSymbol', params, function(results)
            local entries = {}

            local function flatten(symbols)
                for _, sym in ipairs(symbols) do
                    local pos = sym.selectionRange or sym.range
                    local line = pos and pos.start.line + 1 or 0
                    local filename = vim.api.nvim_buf_get_name(opts.buf)

                    table.insert(entries, {
                        data = { filename = filename, line = line },
                        display = make_display_from_lsp_result(filename, sym, line),
                        score = 0,
                    })

                    if sym.children then
                        flatten(sym.children)
                    end
                end
            end

            for _, result in pairs(results) do
                local symbols = result.result or {}

                if symbols[1] and symbols[1].location then
                    -- SymbolInformation[]
                    for _, sym in ipairs(symbols) do
                        local uri = sym.location.uri
                        local line = sym.location.range.start.line + 1
                        local filename = vim.uri_to_fname(uri)

                        table.insert(entries, {
                            data = { filename = filename, line = line },
                            display = make_display_from_lsp_result(filename, sym, line),
                            score = 0,
                        })
                    end
                else
                    flatten(symbols)
                end
            end

            callback(entries)
        end)
    end
    opts[2] = function(e)
        vim.cmd.edit(e.filename)
        vim.api.nvim_win_set_cursor(0, { e.line, 0 })
    end

    M.floating_fuzzy(opts)
end

---@class Finder.LspWorkspaceSymbolsOpts: Finder.FuzzyOpts
function M.lsp_workspace_symbols(opts)
    opts = opts or {}
    opts.buf = opts.buf or vim.api.nvim_get_current_buf()

    opts.live = true
    opts[1] = function(callback, query)
        local params = { query = query or "" }

        vim.lsp.buf_request_all(opts.buf, 'workspace/symbol', params, function(results)
            local entries = {}

            -- Check if we got any results or errors
            if not results or next(results) == nil then
                -- No results, call callback with empty table to avoid hanging
                callback(entries)
                return
            end

            for client_id, result in pairs(results) do
                if result.error then
                    -- Log the error if present, but continue processing other results
                    vim.notify(
                        "LSP workspace/symbol error from client " .. client_id .. ": " .. result.error.message,
                        vim.log.levels.WARN)
                end

                local symbols = result.result or {}

                for _, sym in ipairs(symbols) do
                    local uri = sym.location.uri
                    local line = sym.location.range.start.line + 1
                    local filename = vim.uri_to_fname(uri)
                    table.insert(entries, {
                        data = { filename = filename, line = line },
                        display = make_display_from_lsp_result(filename, sym, line),
                        score = 0,
                    })
                end
            end

            callback(entries)
        end)
    end
    opts[2] = function(e)
        vim.cmd.edit(e.filename)
        vim.api.nvim_win_set_cursor(0, { e.line, 0 })
    end


    M.floating_fuzzy(opts)
end

---@class Finder.ColorschemesOpts: Finder.FuzzyOpts
function M.colorschemes(opts)
    opts = opts or {}
    local colorschemes = vim.fn.getcompletion("", "color")
    local entries = {}
    for _, c in ipairs(colorschemes) do
        table.insert(entries, { display = c, data = c, score = 0 })
    end

    opts[1] = entries
    opts[2] = function(e)
        vim.cmd.colorscheme(e)
    end


    M.floating_fuzzy(opts)
end

return M
