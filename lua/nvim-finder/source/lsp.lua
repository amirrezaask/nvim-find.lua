local M = {}
local shorten_path = require("nvim-finder.path").shorten

local function make_display(filename, sym, line)
    return string.format(
        "[%s] %s - %s",
        sym.kind,
        shorten_path(filename),
        sym.name
    -- line
    )
end

function M.document_symbols(bufnr)
    return function(callback)
        local params = { textDocument = vim.lsp.util.make_text_document_params() }

        vim.lsp.buf_request_all(bufnr, 'textDocument/documentSymbol', params, function(results)
            local entries = {}

            local function flatten(symbols)
                for _, sym in ipairs(symbols) do
                    local pos = sym.selectionRange or sym.range
                    local line = pos and pos.start.line + 1 or 0
                    local filename = vim.api.nvim_buf_get_name(0)
                    table.insert(entries, {
                        entry = { filename = filename, line = line },
                        display = make_display(filename, sym, line),
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
                            entry = { filename = filename, line = line },
                            display = make_display(filename, sym, line),
                            score = 0,
                        })
                    end
                else
                    -- DocumentSymbol[]
                    flatten(symbols)
                end
            end

            callback(entries)
        end)
    end
end

function M.workspace_symbols(bufnr)
    return function(callback)
        local params = { query = "" }

        vim.lsp.buf_request_all(bufnr, 'workspace/symbol', params, function(results)
            local entries = {}

            for _, result in pairs(results) do
                local symbols = result.result or {}

                for _, sym in ipairs(symbols) do
                    local uri = sym.location.uri
                    local line = sym.location.range.start.line + 1
                    local filename = vim.uri_to_fname(uri)
                    table.insert(entries, {
                        entry = { filename = filename, line = line },
                        display = make_display(filename, sym, line),
                        score = 0,
                    })
                end
            end

            callback(entries)
        end)
    end
end

return M
