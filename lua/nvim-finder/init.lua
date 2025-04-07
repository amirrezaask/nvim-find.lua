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
    opts.path = opts.path or vim.fs.root(vim.fn.getcwd(), ".git") or vim.fn.getcwd()
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

function M.ripgrep_qf(cwd)
    vim.ui.input({ prompt = "Ripgrep> " }, function(s)
        if s == nil then return end
        require("nvim-finder.source.ripgrep").qf({
            query = s,
            cwd = cwd or vim.fn.getcwd(),
        })
    end)
end

function M.live_ripgrep(opts)
end

function M.diagnostics()
    require("nvim-finder.fuzzy") {
        title = "Diagnostics",
        require('nvim-finder.source.vim').diagnostics(nil),
        function(e)
            vim.cmd.edit(e.filename)
            vim.api.nvim_win_set_cursor(0, { e.line, 0 })
        end,
    }
end

function M.diagnostics_buffer()
    require("nvim-finder.fuzzy") {
        title = "Diagnostics Buffer",
        require('nvim-finder.source.vim').diagnostics(vim.api.nvim_get_current_buf()),
        function(e)
            vim.cmd.edit(e.filename)
            vim.api.nvim_win_set_cursor(0, { e.line, 0 })
        end,
    }
end

function M.ripgrep_fuzzy(opts)
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

    require("nvim-finder.fuzzy") {
        title = "Buffers",
        require("nvim-finder.source.vim").buffers(opts),
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

function M.oldfiles(opts)
    opts = opts or {}
    opts[1] = {}

    for _, v in ipairs(vim.v.oldfiles) do
        table.insert(opts[1], { entry = v, display = v, score = 0 })
    end

    opts[2] = function(e)
        vim.cmd.edit(e)
    end

    require "nvim-finder.fuzzy" (opts)
end

function M.lsp_document_symbols(opts)
    opts = opts or {}

    opts[1] = require("nvim-finder.source.lsp").document_symbols(vim.api.nvim_get_current_buf())
    opts[2] = function(e)
        vim.print(e)
    end

    require "nvim-finder.fuzzy" (opts)
end

function M.lsp_workspace_symbols(opts)
    opts = opts or {}

    opts[1] = require("nvim-finder.source.lsp").workspace_symbols(vim.api.nvim_get_current_buf())
    opts[2] = function(e)
        vim.print(e)
    end


    require "nvim-finder.fuzzy" (opts)
end

--TODO: navigator function that shows current file directory and you can traverse into directories by recursively calling it again from  on_accept

return M
