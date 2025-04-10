local M = {}
function M.helptags()
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

    return help_tags
end

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


    return buffers
end

function M.diagnostics(bufnr)
    local diags = vim.diagnostic.get(bufnr, {})
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


    return entries
end

return M
