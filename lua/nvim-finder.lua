vim.opt.runtimepath:append("~/src/nvim-finder")
local M = {}

---@class Finder.Entry
---@field entry string
---@field score number
---@field display string

function M.__reload()
    package.loaded["nvim-finder"] = nil
    package.loaded["nvim-finder.alg.fzy"] = nil
    package.loaded["nvim-finder.source.find"] = nil
    package.loaded["nvim-finder.fuzzy"] = nil
end

---@class Finder.FilesOpts
---@field path string path to set as CWD, if not set it will be root of git repository.
---@param opts Finder.FilesOpts
function M.files(opts)
    opts = opts or {}
    opts.path = opts.path or vim.fs.root(vim.fn.expand("%"), ".git")
    require("nvim-finder.source.find")(opts.path,
        function(files)
            vim.schedule(function()
                require("nvim-finder.fuzzy") {
                    files,
                    function(e)
                        vim.cmd.edit(e)
                    end,
                }
            end)
        end)
end

---@class Finder.BuffersOpts
---@param opts Finder.BuffersOpts
function M.buffers(opts)
    opts = opts or {}
    local buffers = {}

    for _, id in ipairs(vim.api.nvim_list_bufs()) do
        table.insert(buffers, { entry = id, display = vim.api.nvim_buf_get_name(id), score = 0 })
    end
    require("nvim-finder.fuzzy") {
        buffers,
        function(e)
            vim.api.nvim_set_current_buf(e)
        end,
    }
end

return M
