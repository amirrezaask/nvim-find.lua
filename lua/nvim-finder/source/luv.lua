local uv = vim.loop
local shorten_path = require("nvim-finder.path").shorten
local expand = require("nvim-finder.path").expand

local function recursive_files(opts)
    opts = opts or {}

    opts.path = expand(opts.path) -- nil check
    if opts.path == nil then return end
    if opts.starting_directory == nil then opts.starting_directory = opts.path end
    opts.hidden = opts.hidden or false
    opts.exclude = opts.exclude or {}
    opts.shorten_paths = opts.shorten_paths or true

    -- Normalize exclude to a list of glob patterns
    local exclude_patterns = {}
    if type(opts.exclude) == "string" then
        exclude_patterns = { opts.exclude }
    elseif vim.islist(opts.exclude) then
        exclude_patterns = opts.exclude
    end

    -- Checks if a path matches any exclude glob
    local function is_excluded(entry_path)
        for _, pattern in ipairs(exclude_patterns) do
            if entry_path:match(pattern) then
                return true
            end
        end
        return false
    end

    return function(cb)
        uv.fs_opendir(opts.path, function(err, dir)
            if err then
                -- log("error reading directory", err)
                return
            end

            local function continue_reading_fs_entries()
                uv.fs_readdir(dir, function(err, entries)
                    if err then
                        uv.fs_closedir(dir)
                        -- log("error in reading directory", err)
                        return
                    end


                    local files = {}

                    if not entries then
                        uv.fs_closedir(dir)
                        return
                    end

                    for _, entry in ipairs(entries) do
                        local entry_path = opts.path .. "/" .. entry.name

                        -- Skip excluded entries based on glob
                        if is_excluded(entry_path) then
                            goto continue
                        end

                        -- Skip hidden files unless opts.hidden is true
                        if not opts.hidden and entry.name:sub(1, 1) == "." then
                            goto continue
                        end

                        if entry.type == 'file' then
                            local display_path = entry_path
                            if opts.shorten_paths then
                                display_path = shorten_path(display_path)
                            end
                            table.insert(files, {
                                data = {
                                    filename = entry_path,
                                },
                                display = display_path,
                                score = 0
                            })
                        elseif entry.type == "directory" then
                            local new_opts = {}
                            for k, v in pairs(opts) do
                                new_opts[k] = v
                            end
                            new_opts.path = entry_path
                            vim.schedule(function()
                                local f = recursive_files(new_opts)
                                if f == nil then return end
                                f(cb)
                            end)
                        end



                        cb(files)

                        ::continue::
                    end

                    continue_reading_fs_entries()
                end)
            end

            continue_reading_fs_entries()
        end)
    end
end

return recursive_files
