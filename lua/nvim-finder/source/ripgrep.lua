local function rg(opts)
    assert(opts)
    assert(opts.query)
    opts.cwd = opts.cwd or vim.fs.root(0, '.git') or vim.fn.expand("%:p:h")
    return function(update_notifier)
        print("rg async called")
        local uv = vim.uv
        local handle
        local stdout = uv.new_pipe(false)
        local stderr = uv.new_pipe(false)
        local path = vim.fn.expand(opts.cwd)

        handle = uv.spawn("rg", {
            args = { "--color", "never", "--column", "-n", "--no-heading", opts.query },
            cwd = path,
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
            if data then
                local lines = vim.split(data, "\n")
                for _, line in ipairs(lines) do
                    if line ~= "" then
                        update_notifier({ entry = line, score = -math.huge, display = line })
                    end
                end
            end
        end)
    end
end

return rg

-- rg {
--     query = "session",
--     cwd = "~/src/doctor/tweety",
-- } (function(e)
--         vim.print(e)
--     end)
