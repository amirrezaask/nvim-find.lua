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
                    table.insert(help_tags, { entry = tag, display = tag, score = 0 })
                end
            end
            f:close()
        end
    end

    return help_tags
end

return M
