return function(path, callback)
    local uv = vim.uv
    local handle
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local results = {}
    path = vim.fn.expand(path)

    handle = uv.spawn("find", {
        args = { path, "-type", "f", "-not", "-path", "**/.git/*", "-not", "-path", "**/vendor/**", },
        stdio = { nil, stdout, stderr },
    }, function(code, signal)
        stdout:read_stop()
        stdout:close()
        handle:close()
        if code == 0 then
            callback(results)
        end
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
                    table.insert(results, { entry = line, score = -math.huge, display = line:sub(#path + 1) })
                end
            end
        end
    end)
end
