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
    package.loaded["nvim-finder.source.luv"] = nil
    package.loaded["nvim-finder.source.ripgrep"] = nil
    package.loaded["nvim-finder.fuzzy"] = nil
end

---@class Finder.FilesOpts
---@field path string path to set as CWD, if not set it will be root of git repository.
---@param opts Finder.FilesOpts
function M.files(opts)
    ---@type Finder.FilesOpts
    opts = opts or {}
    opts.path = opts.path or vim.fs.root(vim.fn.getcwd(), ".git")
    opts.title = 'Files ' .. opts.path
    opts.source = opts.source or 'luv'

    if opts.source == 'luv' then
        opts[1] = require("nvim-finder.source.luv")(opts)
    elseif opts.source == 'find' then
        opts[1] = require("nvim-finder.source.find")(opts)
    else
        vim.fn.error('unsupported source ' .. opts.source)
    end

    opts[2] = function(e)
        vim.cmd.edit(e)
    end

    require("nvim-finder.fuzzy")(opts)
end

function M.ripgrep(cwd)
    vim.ui.input({ prompt = "Ripgrep> " }, function(s)
        if s == nil then return end
        require("nvim-finder.source.ripgrep").qf({
            query = s,
            cwd = cwd or vim.fn.getcwd(),
        })
    end)
end

function M.fuzzy_ripgrep(opts)
    opts = opts or {}
    opts.cwd = opts.cwd or vim.fs.root(vim.fn.getcwd(), '.git')

    vim.ui.input({ prompt = "Fuzzy Ripgrep> " }, function(s)
        if s == nil then return end
        opts[1] = require("nvim-finder.source.ripgrep").fuzzy({ query = s })
        opts[2] = function(e)
            vim.cmd.edit(e.file)
            vim.api.nvim_win_set_cursor(0, { e.line, e.column })
        end
        opts.title = 'Rg ' .. opts.cwd

        require("nvim-finder.fuzzy")(opts)
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
        title = "Buffers",
        buffers,
        function(e)
            vim.api.nvim_set_current_buf(e)
        end,
    }
end

function M.helptags(opts)
    opts = opts or {}
    require("nvim-finder.fuzzy") {
        require("nvim-finder.source.vim").helptags(),
        function(e)
            vim.cmd.help(e)
        end,
    }
end

function M.git_files(opts)
    opts = opts or {}

    require "nvim-finder.fuzzy" {
        require("nvim-finder.source.git").files(opts),
        function(e)
            vim.cmd.edit(e)
        end
    }
end

--TODO: navigator function that shows current file directory and you can traverse into directories by recursively calling it again from  on_accept
--TODO: LSP document symbols and workspace symbols

return M
