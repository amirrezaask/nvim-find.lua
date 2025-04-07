local M = {}

function M.files(opts)
    return function(update_notifier)
        opts.path = opts.path or vim.fs.root(vim.fn.getcwd(), '.git')
        local uv = vim.uv
        local handle
        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)
        opts.path = vim.fn.expand(opts.path)

        --TODO(amirrez): support excludes
        handle = uv.spawn("git", {
            args = { "ls-files" },
            cwd = opts.path,
            stdio = { nil, stdout, stderr },
        }, function(code, signal)
            stdout:read_stop()
            stdout:close()
            handle:close()
        end)

        uv.read_start(stderr, function(err, data)
            if err then
                print("stderr ", err)
                return
            end
            if data then
                print("stderr ", data)
            end
        end)

        uv.read_start(stdout, function(err, data)
            if err then
                vim.schedule(function()
                    print(err)
                end)
                return
            end
            local results = {}
            if data then
                local lines = vim.split(data, "\n")
                for _, line in ipairs(lines) do
                    if line ~= "" then
                        table.insert(results, { entry = line, score = 0, display = line })
                    end
                end

                update_notifier(results)
            end
        end)
    end
end

return M
