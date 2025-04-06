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

-- M.files({ path = "~/src/doctor/core" })

return M
