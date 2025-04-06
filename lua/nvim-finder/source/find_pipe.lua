local function find_pipe(path)
    local uv = vim.uv
    local handle
    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    local output = uv.new_pipe()
    path = vim.fn.expand(path)

    handle = uv.spawn("find", {
        args = { path, "-type", "f", "-not", "-path", "**/.git/*", "-not", "-path", "**/vendor/**", },
        stdio = { nil, stdout, stderr },
    }, function(code, signal)
        stdout:read_stop()
        stdout:close()
        handle:close()
        output:close()
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
                    output:write(line)
                end
            end
        end
    end)


    return output
end


local output = find_pipe("~/src/doctor/consultation")
vim.uv.read_start(output, function(err, data)
    vim.print("HERE")
    if err then print(err) end
    vim.print(data)
end)
